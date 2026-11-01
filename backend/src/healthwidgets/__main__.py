"""``python -m healthwidgets`` / ``healthwidgets-server``: run the API with uvicorn."""

import argparse

import uvicorn


def main() -> None:
    parser = argparse.ArgumentParser(description="Health Widgets sync server")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--reload", action="store_true", help="Auto-reload on code changes (dev)")
    args = parser.parse_args()
    uvicorn.run(
        "healthwidgets.main:create_app",
        factory=True,
        host=args.host,
        port=args.port,
        reload=args.reload,
        proxy_headers=True,
        forwarded_allow_ips="*",
    )


if __name__ == "__main__":
    main()
