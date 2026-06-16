# TrainMate backend — quick start (core API only, no heavy ML install wait)
Set-Location $PSScriptRoot

if (-not (Test-Path ".venv\Scripts\Activate.ps1")) {
    Write-Host "Creating virtual environment..."
    python -m venv .venv
}

Write-Host "Activating venv..."
.\.venv\Scripts\Activate.ps1

Write-Host "Installing core dependencies (fast)..."
python -m pip install --upgrade pip -q
pip install -r requirements.txt -q

if (-not (Test-Path ".env")) {
    Write-Host "Copying .env.example -> .env (edit JWT_SECRET_KEY before production)"
    Copy-Item ".env.example" ".env"
}

Write-Host ""
Write-Host "Starting API on http://127.0.0.1:8000"
Write-Host "Health: http://127.0.0.1:8000/api/health"
Write-Host ""
Write-Host "For exercise classify + body photos (optional, heavy install):"
Write-Host "  pip install -r requirements-ml.txt"
Write-Host ""

uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
