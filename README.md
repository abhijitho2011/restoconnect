# RestoConnect

Production-oriented SaaS scaffold for QR-based restaurant ordering with AR menu support.

## Apps

- `backend` - NestJS REST + Socket.IO API with Prisma/PostgreSQL.
- `frontend_admin_flutter` - Super Admin Flutter Web app.
- `frontend_restaurant_flutter` - Restaurant Owner Flutter Web app.
- `frontend_kitchen_flutter` - Kitchen Dashboard Flutter Web app.
- `frontend_customer_flutter` - Customer QR Flutter Web app with `model-viewer` AR support.

## Backend Quick Start

```bash
cd backend
cp .env.example .env
docker compose up -d postgres
npm install
npm run prisma:migrate
npm run seed
npm run start:dev
```

The API listens on `http://localhost:3000/api` and Socket.IO listens on `http://localhost:3000`.

### Bootstrap Login

Set `SUPER_ADMIN_BOOTSTRAP_PHONE` in `backend/.env`. In dev mode, OTP responses include `devOtp`.

1. Open the admin app.
2. Login with the bootstrap phone and returned OTP.
3. Create a restaurant with an owner mobile number.
4. Approve the restaurant.
5. Owner logs in, creates tables, menu items, and kitchen users.

## Flutter Development

Run each app with the backend URL injected:

```bash
cd frontend_admin_flutter
flutter run -d chrome --web-port 8081 --dart-define=API_BASE_URL=http://localhost:3000/api --dart-define=SOCKET_URL=http://localhost:3000
```

Suggested ports:

- Admin: `8081`
- Restaurant: `8082`
- Kitchen: `8083`
- Customer: `8084`

Customer QR URLs use this shape:

```text
/r/{restaurantId}/t/{tableId}
```

## Production Builds

```bash
flutter build web --release --dart-define=API_BASE_URL=https://api.example.com/api --dart-define=SOCKET_URL=https://api.example.com
```

Upload each app's `build/web` directory to its own S3 bucket or prefix and serve through CloudFront. Configure CloudFront custom error responses so SPA routes return `index.html`.

## Core API

- `POST /api/auth/send-otp`
- `POST /api/auth/verify-otp`
- `POST /api/restaurants`
- `GET /api/restaurants`
- `PATCH /api/restaurants/:id/status`
- `POST /api/tables`
- `GET /api/tables?restaurantId=...`
- `POST /api/menu/categories`
- `GET /api/menu/categories?restaurantId=...`
- `POST /api/menu/items`
- `PATCH /api/menu/items/:id`
- `GET /api/menu/public/:restaurantId`
- `POST /api/orders`
- `GET /api/orders`
- `GET /api/orders/table/:restaurantId/:tableId`
- `PATCH /api/orders/:id/status`
- `POST /api/uploads/signed-url`
- `POST /api/payments/razorpay/orders`

## Realtime Events

Socket.IO emits:

- `order_created`
- `order_updated`
- `order_completed`

Kitchen and restaurant apps authenticate sockets with JWT auth. Customer sockets join by `restaurantId` and `tableId` query parameters.

## Validation

The generated project has been checked with:

```bash
cd backend && npm run prisma:generate && npm run build
cd frontend_admin_flutter && flutter analyze
cd frontend_restaurant_flutter && flutter analyze
cd frontend_kitchen_flutter && flutter analyze
cd frontend_customer_flutter && flutter analyze
```
