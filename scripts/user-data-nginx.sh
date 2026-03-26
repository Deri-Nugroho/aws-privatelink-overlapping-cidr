#!/bin/bash
# Instalasi melalui AWS-managed repositories via S3 Gateway Endpoint
yum update -y
yum install nginx -y
systemctl start nginx
systemctl enable nginx
echo "<h1>Welcome to Nginx via PrivateLink</h1>" > /usr/share/nginx/html/index.html
