# AWS Deployment Guide

## 1. PostgreSQL on RDS

Create an RDS PostgreSQL 16 instance in private subnets.

Recommended settings:

- Multi-AZ for production.
- Storage autoscaling enabled.
- Security group allows inbound PostgreSQL from ECS tasks only.
- Enable automated backups and Performance Insights.

Set the backend `DATABASE_URL`:

```text
postgresql://USER:PASSWORD@RDS_ENDPOINT:5432/restoconnect?schema=public
```

## 2. S3 Storage

Create one private asset bucket for menu images and AR files.

Suggested prefixes:

- `images/{restaurantId}/...`
- `ar-models/{restaurantId}/...`

Use CloudFront in front of this bucket and set:

```text
AWS_S3_BUCKET=your-asset-bucket
AWS_PUBLIC_ASSET_BASE_URL=https://assets.example.com
```

Grant the ECS task role `s3:PutObject` for the bucket.

## 3. Backend on ECS Fargate

Build and push the image:

```bash
cd backend
aws ecr create-repository --repository-name restoconnect-backend
docker build -t restoconnect-backend .
docker tag restoconnect-backend:latest ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/restoconnect-backend:latest
docker push ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/restoconnect-backend:latest
```

Create an ECS Fargate service behind an Application Load Balancer.

Task settings:

- Container port: `3000`
- Health check path: `/api/health`
- CPU/memory: start with `0.5 vCPU / 1GB`
- Desired count: at least `2` in production
- Environment variables from AWS Secrets Manager or SSM Parameter Store

Socket.IO works through ALB with WebSocket support enabled by default. Use sticky sessions if you run multiple tasks without Redis adapter. For larger scale, add ElastiCache Redis and configure a Socket.IO Redis adapter.

## 4. Frontend on S3 + CloudFront

Build each app:

```bash
flutter build web --release \
  --dart-define=API_BASE_URL=https://api.example.com/api \
  --dart-define=SOCKET_URL=https://api.example.com
```

Deploy:

```bash
aws s3 sync build/web s3://your-app-bucket --delete
aws cloudfront create-invalidation --distribution-id DIST_ID --paths "/*"
```

For Flutter SPA routes, configure CloudFront custom error responses:

- 403 -> `/index.html`, HTTP 200
- 404 -> `/index.html`, HTTP 200

Use separate CloudFront distributions or hostnames:

- `admin.example.com`
- `restaurant.example.com`
- `kitchen.example.com`
- `menu.example.com`

Set backend `CORS_ORIGINS` to those exact origins.

## 5. Production Environment Checklist

- Use a strong `JWT_SECRET`.
- Set `OTP_DEV_MODE=false` and connect a real SMS provider in `OtpService`.
- Store secrets in Secrets Manager or SSM, not task definitions.
- Restrict RDS and S3 access to private networks and IAM roles.
- Enable ALB access logs, ECS logs, RDS backups, and CloudWatch alarms.
- Run `npx prisma migrate deploy` during deployment.
- Configure Razorpay keys only in production/staging secret stores.
