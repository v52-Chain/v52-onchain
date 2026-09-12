/**
 * x402 Test — Verificar respuesta 402
 * =====================================
 * Script auxiliar que hace un request sin pago al seller
 * para verificar que devuelve HTTP 402 con las instrucciones correctas.
 *
 * Uso:
 *   npm run test:402
 */

import "dotenv/config";

const SELLER_URL = process.env.SELLER_URL || "http://localhost:4021";

async function test402(): Promise<void> {
  console.log("=".repeat(60));
  console.log("🧪 Test: Verificar respuesta HTTP 402");
  console.log("=".repeat(60));
  console.log();

  const weatherUrl = `${SELLER_URL}/weather`;
  console.log(`📡 GET ${weatherUrl} (sin header de pago)`);
  console.log();

  try {
    const response = await fetch(weatherUrl);

    console.log(`Status: ${response.status} ${response.statusText}`);
    console.log();

    // Listar todos los headers relevantes
    console.log("Headers relevantes:");
    for (const [key, value] of response.headers.entries()) {
      if (
        key.toLowerCase().includes("payment") ||
        key.toLowerCase().includes("x-")
      ) {
        console.log(
          `  ${key}: ${value.substring(0, 200)}${value.length > 200 ? "..." : ""}`
        );
      }
    }
    console.log();

    if (response.status === 402) {
      console.log("✅ Correcto: el servidor retornó HTTP 402 Payment Required");

      // Intentar parsear el header PAYMENT-REQUIRED (es base64 en x402 V2)
      const paymentRequired = response.headers.get("payment-required");
      if (paymentRequired) {
        try {
          const decoded = Buffer.from(paymentRequired, "base64").toString("utf-8");
          const parsed = JSON.parse(decoded);
          console.log();
          console.log("📋 Instrucciones de pago (PAYMENT-REQUIRED header decodificado):");
          console.log(JSON.stringify(parsed, null, 2));
        } catch {
          console.log("   (No se pudo parsear como JSON/base64)");
          console.log("   Raw:", paymentRequired.substring(0, 500));
        }
      } else {
        console.log("⚠️  No se encontró el header PAYMENT-REQUIRED");
      }
    } else {
      console.log(`⚠️  Esperado 402 pero recibido ${response.status}`);
      const body = await response.text();
      console.log("Body:", body.substring(0, 500));
    }
  } catch (error: unknown) {
    console.error("💥 Error al conectar con el seller:");
    if (error instanceof Error) {
      console.error("   ", error.message);
    } else {
      console.error("   ", error);
    }
  }

  console.log();
  console.log("=".repeat(60));
}

test402();
