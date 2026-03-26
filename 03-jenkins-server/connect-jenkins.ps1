Write-Host "[*] Finding Jenkins-Master server on AWS (Region: ap-southeast-1)..." -ForegroundColor Cyan

# 1. Tìm Instance ID dựa vào Tag
$INSTANCE_ID = aws ec2 describe-instances `
    --filters "Name=tag:Name,Values=Jenkins-Master" "Name=instance-state-name,Values=running" `
    --query "Reservations[*].Instances[*].InstanceId" `
    --output text

# Cắt khoảng trắng thừa
$INSTANCE_ID = $INSTANCE_ID.Trim()

# 2. Xử lý ngoại lệ (Assumptions: Máy chủ có thể chưa bật hoặc chưa tạo xong)
if ([string]::IsNullOrWhiteSpace($INSTANCE_ID)) {
    Write-Host "[ERROR] No running Jenkins server found! Have you run Terraform Apply?" -ForegroundColor Red
    Exit
}

Write-Host "[OK] Target Instance ID: $INSTANCE_ID" -ForegroundColor Green
Write-Host "[*] Setting up Zero-Trust tunnel via AWS SSM..." -ForegroundColor Yellow
Write-Host "[*] Once tunnel is open, access: http://localhost:8080" -ForegroundColor Yellow
Write-Host "[WARNING] Press Ctrl+C in this window to close tunnel when done" -ForegroundColor DarkGray
Write-Host "------------------------------------------------------------------"

# 3. Activate Port-Forward session
aws ssm start-session `
    --target $INSTANCE_ID `
    --document-name AWS-StartPortForwardingSession `
    --parameters "portNumber=8080,localPortNumber=8080"