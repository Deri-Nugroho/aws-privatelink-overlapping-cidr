# AWS PrivateLink Solution: Overlapping CIDR Challenge

![AWS Architecture Diagram](assets/Overlapping_CIDR_VPC_Peering.drawio.png)

---

## 📌 Overview
Project ini mendokumentasikan implementasi **AWS PrivateLink** sebagai solusi untuk mengatasi konflik routing pada VPC dengan CIDR identik (**VPC A & VPC C: 10.0.0.0/16**). Arsitektur ini mengadopsi prinsip **Zero Trust & Cost-Efficient**, memastikan layanan tetap terisolasi tanpa memerlukan Internet Gateway, NAT Gateway, maupun Public IP.

---

- VPC A: `10.0.0.0/16`
- VPC C: `10.0.0.0/16`

Arsitektur ini mengadopsi prinsip:

- 🔐 Zero Trust
- 💰 Cost-Efficient
- 🌐 Tanpa Internet Gateway, NAT Gateway, dan Public IP

---

## 🎯 Key Takeaways

- **Overlapping Resolution**  
  PrivateLink menghindari ketergantungan pada routing Layer 3 (CIDR) ❌

- **Layer 4 Communication**  
  Konektivitas berjalan di level TCP melalui AWS Backbone Network

- **Service-Level Abstraction**  
  Fokus berpindah dari network-peering ke service-access

- **Egress Control**  
  Menggunakan S3 Gateway Endpoint (tanpa NAT Gateway)

- **Zero Inbound Management**  
  Akses EC2 via AWS Systems Manager (SSM), tanpa buka port 22

---

## 💡 Arsitektur Logic (Golden Answer)

### ❓ Mengapa Tidak Terjadi Konflik Routing?

AWS PrivateLink bekerja di **Layer 4 (TCP)** dan tidak menggunakan routing antar VPC.

Sebagai gantinya:

- Consumer VPC memiliki **Interface Endpoint (ENI)** dengan IP lokal
- Trafik dikirim ke **Network Load Balancer (NLB)** di Provider VPC
- Komunikasi lewat **AWS internal backbone network**

👉 **Tidak ada pertukaran CIDR → tidak ada konflik overlapping**

---

## I. 🏗️ Persiapan Infrastruktur

### A. Provider (VPC B - 10.1.0.0/16)

- Buat VPC: `VPC-B-Provider`
- CIDR: `10.1.0.0/16`
- Subnet: Private Subnet (misal `us-east-1a`)

#### S3 Gateway Endpoint (WAJIB)
Digunakan agar EC2 bisa install package tanpa internet:

- Associate ke Route Table VPC B

---

### B. Consumer (VPC A & VPC C - 10.0.0.0/16)

- VPC:
  - `VPC-A-Consumer`
  - `VPC-C-Consumer`
- CIDR: `10.0.0.0/16` (identik)
- Subnet: Private Subnet (AZ sama dengan provider)

#### DNS Settings
Aktifkan:
- Enable DNS Hostnames
- Enable DNS Resolution

---

## II. 🔐 Konfigurasi Security Groups

### A. Provider (VPC B)

#### SG-Nginx-Provider

- **Inbound**
  - TCP 80 → Source: `10.1.0.0/16`

- **Outbound**
  - HTTPS 443 → Destination: S3 Prefix List

---

### B. Consumer (VPC A & C)

#### SG-EC2-Client

- **Inbound**
  - None

- **Outbound**
  - TCP 443 → SG-VPCE-SSM
  - TCP 80 → SG-VPCE-Privatelink

---

#### SG-VPCE-SSM

- **Inbound**
  - TCP 443 → Source: SG-EC2-Client

---

#### SG-VPCE-Privatelink

- **Inbound**
  - TCP 80 → Source: SG-EC2-Client

---

## III. ⚙️ Deployment Compute & Load Balancer

### A. Provider Side (VPC B)

#### EC2 Nginx Server

- IAM Role: `AmazonSSMManagedInstanceCore`
- Security Group: `SG-Nginx-Provider`

**User Data:**
```bash
#!/bin/bash
yum update -y
yum install nginx -y
systemctl start nginx
systemctl enable nginx
echo "<h1>Welcome to Nginx via PrivateLink</h1>" > /usr/share/nginx/html/index.html
```

#### Network Load Balancer (NLB)
Scheme: Internal
Listener: TCP 80
Target Group: EC2 Nginx

### B. Consumer Side (VPC A & C)

#### EC2 Client
- IAM Role: `AmazonSSMManagedInstanceCore`
- Security Group: `SG-EC2-Client`

## IV. 🔗 Implementasi AWS PrivateLink

### A. Endpoint Service (Provider - VPC B)
- Hubungkan ke NLB
- Enable: `Acceptance Required `

Contoh Service Name:
`com.amazonaws.vpce.us-east-1.vpce-svc-xxxx `
 
### B. Interface Endpoints (Consumer)

## 1. SSM Endpoints (3 Required)
- `ssm `
- `ssmmessages `
- `ec2messages `

Gunakan:
- SG: `SG-VPCE-SSM `
- Enable Private DNS

## 2. Nginx Interface Endpoint
- Pilih: Other endpoint services
- Masukkan Service Name dari provider
- SG: SG-VPCE-Privatelink
- Subnet: AZ yang sama dengan EC2

### C. DNS Mapping (Route 53)

- Private Hosted Zone:
`service.local `

Record:
`nginx.service.local → Alias ke Interface Endpoint DNS `

## V. 🧪 Testing & Verification

### A. Acceptance
- Masuk ke:
  - VPC B → Endpoint Connections
- Klik:
  - Accept
  - 
### B. Connectivity Test

Masuk ke EC2 via SSM Session Manager

## 1. DNS Check
```bash
nslookup nginx.service.local
```

## 2. Port Check
```bash
timeout 2 bash -c '</dev/tcp/nginx.service.local/80' && echo "PORT OPEN" || echo "PORT CLOSED"
```

## 3. HTTP Request
```bash
curl -Iv http://nginx.service.local
```

### ✅ Expected Result
- HTTP 200 OK
- Koneksi sukses
- Tidak ada konflik CIDR

## VI. ⚖️ Trade-offs Analysis

### ✅ Pros
- Solusi bersih untuk overlapping CIDR
- High security (no inbound exposure)
- Cost-efficient (no NAT Gateway)

### ❌ Cons
- Setup lebih kompleks
- Hanya komunikasi satu arah (consumer → provider)

### 🔄 Alternative
- NAT Gateway
  ❌ Mahal
  ❌ Menambah attack surface

## 🏁 Kesimpulan

Arsitektur ini:
- Menghilangkan kebutuhan internet publik
- Mengurangi biaya operasional
- Meningkatkan keamanan secara signifikan

Dengan pendekatan:
`Service-Level Communication over Network-Level Connectivity`

## 🧠 Author Notes
Project ini menunjukkan pendekatan Architect-level thinking dalam:
- Network isolation
- Cost optimization
- Zero Trust implementation
- Cloud-native design
