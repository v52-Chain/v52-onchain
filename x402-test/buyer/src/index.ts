/**
 * x402 Buyer — Node.js TypeScript Client
 * ========================================
 * Cliente que realiza requests con pago automático x402.
 *
 * Flujo:
 * 1. Hace GET al seller → recibe HTTP 402 con instrucciones de pago
 * 2. El wrapper de x402 firma automáticamente el payload de pago
 * 3. Reenvía el request con el header PAYMENT-SIGNATURE
 * 4. Recibe la respuesta del seller (200) si el pago fue válido
 *
 * Red: Avalanche Fuji Testnet (eip155:43113)
 * Token: USDC Testnet
 *
 * Uso:
 *   cp ../.env.example ../.env   # Editar con valores reales
 *   npm install
 *   npm start
 */

import dotenv from "dotenv";
import path from "path";
dotenv.config({ path: path.resolve(process.cwd(), "../.env") });
dotenv.config();

import { wrapFetchWithPayment, x402HTTPClient } from "@x402/fetch";
import { x402Client } from "@x402/core/client";
import { ExactEvmScheme } from "@x402/evm/exact/client";
import { privateKeyToAccount } from "viem/accounts";

// ---------------------------------------------------------------------------
// 1. Validar variables de entorno
// ---------------------------------------------------------------------------
let BUYER_PRIVATE_KEY = process.env.BUYER_PRIVATE_KEY;
const SELLER_URL = process.env.SELLER_URL || "http://localhost:4021";

if (!BUYER_PRIVATE_KEY) {
  console.error("❌ ERROR: BUYER_PRIVATE_KEY no está definida en .env");
  process.exit(1);
}

// Asegurar que la private key tiene el prefijo 0x
if (!BUYER_PRIVATE_KEY.startsWith("0x")) {
  BUYER_PRIVATE_KEY = `0x${BUYER_PRIVATE_KEY}`;
}

// ---------------------------------------------------------------------------
// 2. Crear wallet signer desde la private key
// ---------------------------------------------------------------------------
console.log("=".repeat(60));
console.log("💳 x402 Buyer — Payment Client");
console.log("=".repeat(60));

const signer = privateKeyToAccount(BUYER_PRIVATE_KEY as `0x${string}`);
console.log(`  Wallet:     ${signer.address}`);
console.log(`  Seller URL: ${SELLER_URL}`);

// ---------------------------------------------------------------------------
// 3. Crear x402 client y registrar el scheme EVM
// ---------------------------------------------------------------------------
// Para el cálculo de la firma EIP-712 (EIP-3009), la librería @x402/evm
// requiere el formato CAIP-2 "eip155:43113" para extraer el chainId (43113 = Avalanche Fuji).
// Mapeamos el alias "avalanche:fuji" a "eip155:43113" durante la creación del payload.
class FujiExactEvmScheme extends ExactEvmScheme {
  override async createPaymentPayload(
    x402Version: number,
    paymentRequirements: any,
    context?: any
  ) {
    const mappedRequirements = {
      ...paymentRequirements,
      network:
        paymentRequirements.network === "avalanche:fuji"
          ? "eip155:43113"
          : paymentRequirements.network,
    };
    return await super.createPaymentPayload(
      x402Version,
      mappedRequirements,
      context
    );
  }
}

const client = new x402Client();
client.spendControls = false;
const evmScheme = new FujiExactEvmScheme(signer);
client.register("avalanche:fuji", evmScheme);
client.register("eip155:43113", evmScheme);
client.register("eip155:*", evmScheme);

// ---------------------------------------------------------------------------
// 4. Wrappear fetch con manejo de pagos automático
// ---------------------------------------------------------------------------
const fetchWithPayment = wrapFetchWithPayment(fetch, client);
const httpClient = new x402HTTPClient(client);

// ---------------------------------------------------------------------------
// 5. Ejecutar la prueba
// ---------------------------------------------------------------------------
async function runTest(): Promise<void> {
  const weatherUrl = `${SELLER_URL}/weather`;
  console.log();
  console.log("=".repeat(60));
  console.log(`🌤️  Solicitando: GET ${weatherUrl}`);
  console.log("=".repeat(60));
  console.log();

  try {
    // ----- Paso A: Health check (sin pago) -----
    console.log("📋 Paso 1: Health check (sin pago)...");
    const healthResponse = await fetch(`${SELLER_URL}/health`);
    const healthData = await healthResponse.json();
    console.log("   ✅ Health:", JSON.stringify(healthData, null, 2));
    console.log();

    // ----- Paso B: Request con pago automático -----
    console.log("💰 Paso 2: Request con pago automático a /weather...");
    console.log(
      "   (el wrapper x402 manejará el flujo 402 → firma → retry)"
    );
    console.log();

    const response = await fetchWithPayment(weatherUrl, {
      method: "GET",
    });

    // ----- Paso C: Procesar la respuesta -----
    console.log("📦 Paso 3: Resultado recibido");
    console.log("   Status HTTP:", response.status, response.statusText);
    console.log("   Headers:");
    for (const [k, v] of response.headers.entries()) {
      console.log(`     ${k}: ${v}`);
    }

    const result = await httpClient.processResponse(response);
    console.log();
    console.log("   Body:");
    console.log("   ", JSON.stringify(result.body, null, 2));
    console.log();

    // ----- Paso D: Verificar estado del pago -----
    if (result.paymentStatus === "settled") {
      console.log("✅ Paso 4: ¡Pago liquidado exitosamente!");
      console.log(
        "   Payment header:",
        JSON.stringify(result.header, null, 2)
      );
    } else if (result.paymentStatus === "settle_failed") {
      console.error("❌ Paso 4: Liquidación del pago falló");
      console.error("   Header:", JSON.stringify(result.header, null, 2));
    } else if (result.paymentStatus === "none") {
      console.log("ℹ️  Paso 4: No se detectó pago en la respuesta");
    } else {
      console.log(`⚠️  Paso 4: Estado de pago: ${result.paymentStatus}`);
    }
  } catch (error: unknown) {
    console.error();
    console.error("💥 Error durante la prueba:");
    if (error instanceof Error) {
      console.error("   Mensaje:", error.message);
      console.error("   Stack:", error.stack);
    } else {
      console.error("   ", error);
    }
    process.exit(1);
  }

  console.log();
  console.log("=".repeat(60));
  console.log("🏁 Prueba completada");
  console.log("=".repeat(60));
}

runTest();
