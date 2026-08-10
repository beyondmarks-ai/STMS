# STMS RTSP edge connector

The edge connector runs on a Windows/Linux computer on the same private network as the college IP camera. It reads RTSP locally and sends short MP4 segments to the Azure STMS API over HTTPS. Camera credentials are held only in memory and are never sent to Azure.

## Run on the college gateway

FFmpeg and FFprobe must be installed and available on `PATH`.

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r edge\requirements.txt
Copy-Item edge\.env.example edge\.env
# Edit EDGE_CONNECTOR_TOKEN in edge\.env before starting.
uvicorn edge.app:app --host 0.0.0.0 --port 8090
```

Allow inbound TCP `8090` only on the private/domain Windows Firewall profile. Do not forward port `8090` or camera port `554` through the college router.

Open `http://GATEWAY-LAN-IP:8090/health` from the phone. The response should show `configured: true` and `ffmpeg: true`. Then enter that gateway URL, the same pairing token, camera name and RTSP URL in STMS → Video jobs → Live IP camera.

The connector defaults to an 8-second segment every 60 seconds. This is a near-live demonstration profile designed not to overload the single Azure worker. It automatically retries camera or upload failures. A production multi-camera deployment should use a durable queue and dedicated workers.
