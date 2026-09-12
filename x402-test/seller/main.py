"""
x402 Seller - FastAPI Server
=============================
Servidor que expone un endpoint GET /weather protegido por x402.

Flujo:
1. Un request sin pago recibe HTTP 402 con instrucciones de pago en el header PAYMENT-REQUIRED
2. Un request con header PAYMENT-SIGNATURE valido recibe la respuesta normal (200)

Red: Avalanche Fuji Testnet (eip155:43113)
Token: USDC Testnet (0x5425890298aed601595a70AB815c96711a31Bc65, 6 decimals)
Facilitador: OpenZeppelin Relayer con plugin x402

Uso:
    cp ../.env.example ../.env   # Editar con valores reales
    pip install -r requirements.txt
    python main.py
"""

import os
import sys
from pathlib import Path
from typing import Any

from dotenv import load_dotenv
from fastapi import FastAPI

from x402.http import FacilitatorConfig, HTTPFacilitatorClient, PaymentOption
from x402.http.middleware.fastapi import PaymentMiddlewareASGI
from x402.http.types import RouteConfig
from x402.mechanisms.evm.exact import ExactEvmServerScheme
from x402.schemas import Network
from x402.server import x402ResourceServer

# ---------------------------------------------------------------------------
# 1. Cargar variables de entorno
# ---------------------------------------------------------------------------
# Buscar .env en el directorio del script y en el padre (x402-test/)
script_dir = Path(__file__).resolve().parent
env_path = script_dir.parent / ".env"
if not env_path.exists():
    env_path = script_dir / ".env"
load_dotenv(dotenv_path=env_path)

FACILITATOR_URL = os.getenv("FACILITATOR_URL")
FACILITATOR_API_KEY = os.getenv("FACILITATOR_API_KEY")
SELLER_WALLET_ADDRESS = os.getenv("SELLER_WALLET_ADDRESS")
SELLER_PORT = int(os.getenv("SELLER_PORT", "4021"))

if not FACILITATOR_URL:
    print("[ERROR] FACILITATOR_URL no esta definida en .env")
    print(f"  .env buscado en: {env_path}")
    sys.exit(1)

if not SELLER_WALLET_ADDRESS:
    print("[ERROR] SELLER_WALLET_ADDRESS no esta definida en .env")
    sys.exit(1)

if not FACILITATOR_API_KEY:
    print("[WARN] FACILITATOR_API_KEY no esta definida - el facilitador podria rechazar requests")

# ---------------------------------------------------------------------------
# 2. Configuracion de red y token
# ---------------------------------------------------------------------------
# Avalanche Fuji Testnet (formato CAIP-2)
AVAX_FUJI_NETWORK: Network = "eip155:43113"

# USDC Testnet en Avalanche Fuji (Aave/Circle)
USDC_FUJI_ADDRESS = "0x5425890298aed601595a70AB815c96711a31Bc65"

# Precio: 1000 atomic units = $0.001 USDC (USDC tiene 6 decimals)
PAYMENT_AMOUNT = "1000"

# ---------------------------------------------------------------------------
# 3. Proveedor de autenticación Bearer para OpenZeppelin Relayer
# ---------------------------------------------------------------------------
from x402.http.facilitator_client import AuthHeaders

class BearerAuthProvider:
    """Inyecta el token Bearer requerido por el plugin x402 de OpenZeppelin."""
    def __init__(self, token: str):
        self._headers = {"Authorization": f"Bearer {token}"}

    def get_auth_headers(self) -> AuthHeaders:
        return AuthHeaders(
            verify=self._headers,
            settle=self._headers,
            supported=self._headers,
            bazaar=self._headers,
        )

# ---------------------------------------------------------------------------
# 4. Crear la app FastAPI
# ---------------------------------------------------------------------------
app = FastAPI(
    title="x402 Seller - Weather API",
    description="Endpoint de prueba protegido por pagos x402 en Avalanche Fuji",
    version="1.0.0",
)

# ---------------------------------------------------------------------------
# 5. Configurar el facilitador (OpenZeppelin Relayer con plugin x402)
# ---------------------------------------------------------------------------
auth_provider = BearerAuthProvider(FACILITATOR_API_KEY) if FACILITATOR_API_KEY else None
facilitator_config = FacilitatorConfig(
    url=FACILITATOR_URL,
    auth_provider=auth_provider,
)
facilitator = HTTPFacilitatorClient(facilitator_config)

# ---------------------------------------------------------------------------
# 6. Crear el resource server y registrar el scheme EVM para Fuji
# ---------------------------------------------------------------------------
server = x402ResourceServer(facilitator)
server.register(AVAX_FUJI_NETWORK, ExactEvmServerScheme())

# ---------------------------------------------------------------------------
# 7. Definir rutas protegidas por x402
# ---------------------------------------------------------------------------
routes: dict[str, RouteConfig] = {
    "GET /weather": RouteConfig(
        accepts=[
            PaymentOption(
                scheme="exact",
                pay_to=SELLER_WALLET_ADDRESS,
                price={
                    "amount": PAYMENT_AMOUNT,
                    "asset": USDC_FUJI_ADDRESS,
                    "extra": {
                        "name": "USD Coin",
                        "version": "2",
                        "areFeesSponsored": True,
                    },
                },
                network=AVAX_FUJI_NETWORK,
                max_timeout_seconds=300,
            ),
        ],
        mime_type="application/json",
        description="Weather report - test endpoint protegido por x402",
    ),
}

# ---------------------------------------------------------------------------
# 8. Agregar el middleware de pago
# ---------------------------------------------------------------------------
app.add_middleware(PaymentMiddlewareASGI, routes=routes, server=server)

# ---------------------------------------------------------------------------
# 8. Endpoint protegido
# ---------------------------------------------------------------------------
@app.get("/weather")
async def get_weather() -> dict[str, Any]:
    """
    Retorna un reporte del clima de prueba.
    Este endpoint solo es accesible despues de un pago x402 valido.
    """
    return {
        "report": {
            "city": "Avalanche City",
            "weather": "sunny",
            "temperature": 25,
            "humidity": 45,
            "wind_speed": 12,
            "description": "Cielo despejado, perfecto para transacciones on-chain",
        },
        "payment": {
            "network": str(AVAX_FUJI_NETWORK),
            "token": "USDC (Fuji Testnet)",
            "amount_charged": PAYMENT_AMOUNT,
        },
    }


# ---------------------------------------------------------------------------
# 9. Endpoint de health check (sin pago)
# ---------------------------------------------------------------------------
@app.get("/health")
async def health() -> dict[str, str]:
    """Health check - no requiere pago."""
    return {
        "status": "ok",
        "service": "x402-seller-test",
        "network": str(AVAX_FUJI_NETWORK),
        "facilitator": FACILITATOR_URL,
    }


# ---------------------------------------------------------------------------
# 10. Iniciar servidor
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    import uvicorn

    print("=" * 60)
    print("  x402 Seller - Weather API")
    print("=" * 60)
    print(f"  Red:          {AVAX_FUJI_NETWORK}")
    print(f"  Token:        USDC @ {USDC_FUJI_ADDRESS}")
    print(f"  Precio:       {PAYMENT_AMOUNT} atomic units ($0.001 USDC)")
    print(f"  Pay To:       {SELLER_WALLET_ADDRESS}")
    print(f"  Facilitador:  {FACILITATOR_URL}")
    api_display = "***" + FACILITATOR_API_KEY[-6:] if FACILITATOR_API_KEY else "N/A"
    print(f"  API Key:      {api_display}")
    print(f"  Puerto:       {SELLER_PORT}")
    print("=" * 60)
    print()
    print("  Endpoints:")
    print(f"  GET http://localhost:{SELLER_PORT}/weather  (protegido por x402)")
    print(f"  GET http://localhost:{SELLER_PORT}/health   (sin pago)")
    print()

    uvicorn.run(app, host="0.0.0.0", port=SELLER_PORT)
