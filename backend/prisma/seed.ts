import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

async function main(): Promise<void> {
  await prisma.subscriptionPlan.upsert({
    where: { code: "STARTER" },
    update: {},
    create: {
      code: "STARTER",
      name: "Starter",
      monthlyPricePaise: 199900,
      features: ["QR ordering", "Kitchen dashboard", "AR menu assets"],
    },
  });

  await prisma.subscriptionPlan.upsert({
    where: { code: "GROWTH" },
    update: {},
    create: {
      code: "GROWTH",
      name: "Growth",
      monthlyPricePaise: 499900,
      features: [
        "Everything in Starter",
        "Advanced analytics",
        "Priority support",
      ],
    },
  });
}

main()
  .then(async () => prisma.$disconnect())
  .catch(async (error) => {
    console.error(error);
    await prisma.$disconnect();
    process.exit(1);
  });
