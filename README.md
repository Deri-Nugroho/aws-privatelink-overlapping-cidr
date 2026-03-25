# AWS PrivateLink Solution: Overlapping CIDR Challenge

![AWS Architecture Diagram](Overlapping_CIDR_VPC_Peering.drawio.png)

---

## 📌 Overview

Project ini mendokumentasikan implementasi **AWS PrivateLink** sebagai solusi untuk mengatasi konflik routing pada VPC dengan CIDR identik:

* **VPC A** → `10.0.0.0/16`
* **VPC C** → `10.0.0.0/16` (Overlapping)
* **VPC B** → Provider (Nginx Service)

Pendekatan ini dipilih karena kebutuhan hanya sebatas **service access (HTTP)**, bukan **full network connectivity** antar VPC.

---

## 🎯 Key Takeaways

* Overlapping CIDR tidak bisa diselesaikan dengan VPC Peering ❌
* AWS PrivateLink menghindari dependency pada routing berbasis CIDR
* Komunikasi terjadi di **Layer 4 (TCP)**, bukan Layer 3
* Menggunakan **service-level abstraction** (bukan network-level)

---

## 💡 Arsitektur Logic (Golden Answer)

### Mengapa Tidak Terjadi Konflik Routing?

AWS PrivateLink bekerja pada **Layer 4 (TCP)** dan tidak menggunakan tabel routing antar VPC. Sebagai gantinya:

1. Setiap VPC Consumer memiliki **Interface Endpoint (ENI)** dengan IP lokal  
2. Trafik dikirim melalui **AWS Backbone Network**  
3. Trafik diarahkan ke **Network Load Balancer (NLB)** di VPC Provider  

👉 Karena tidak ada routing berbasis CIDR antar VPC,  
**overlapping CIDR tidak menjadi masalah**

---

# I. Persiapan Infrastruktur VPC

## A. Provider (VPC B - 10.1.0.0/16)

### 1. Dasar Jaringan
* **VPC Name:** `VPC-B-Provider`  
* **CIDR:** `10.1.0.0/16`  
* **Subnet:** `VPC-B-Private-Subnet-1`  
  - AZ: `us-east-1a`  
  - CIDR: `10.1.1.0/24`  

---

### 2. Deploy Nginx Server (EC2)

**User Data Script:**

```bash
#!/bin/bash
yum update -y
yum install nginx -y
systemctl start nginx
systemctl enable nginx
echo "<h1>Welcome to Nginx via PrivateLink</h1>" > /usr/share/nginx/html/index.html
```

**Security Group (SG-Nginx-Provider):**
- Inbound: Allow TCP 80
- Source: CIDR subnet NLB (bukan 0.0.0.0/0)

### 3. Target Group
- Name: TG-Nginx-80
- Protocol: TCP
- Port: 80
- Target: EC2 Nginx Instance

## B. Consumer (VPC A & VPC C - 10.0.0.0/16)
### 1. VPC & Subnet (Overlapping)
- VPC A & C: 10.0.0.0/16
- Subnet: 10.0.1.0/24
- 
### 2. Client EC2
- Digunakan sebagai testing instance
- Security Group:
   - Allow SSH / ICMP dari IP lokal
 
# II. Implementasi PrivateLink

## A. Network Load Balancer (VPC B)
- Name: NLB-PrivateLink
- Scheme: Internal
- Listener: TCP 80 → Forward ke Target Group

## B. Endpoint Service (VPC B)
- Attach ke NLB
- Enable Acceptance Required
### Contoh Service Name:

```bash
com.amazonaws.vpce.us-east-1.vpce-svc-xxx
```

## C. Interface Endpoint (VPC A & VPC C)
- Service Category: Other endpoint services
- Paste Service Name dari VPC B

### Security Group Endpoint:
- Inbound: TCP 80 dari EC2 client
- Outbound: Allow All

### Private DNS:
- Enabled
- Contoh: nginx.service.local

# III. Testing & Verification
## A. Accept Connection (VPC B)
- Endpoint Services → Accept request dari VPC A & C

## B. Testing dari Client

```bash
curl -Iv http://<endpoint-dns-atau-private-dns>
```

## ✅ Expected Result
- Client A & Client C berhasil akses Nginx
- Tidak ada konflik routing meskipun CIDR overlap

## 🔍 Source IP Behavior
- Nginx akan melihat IP dari NLB node
- Bukan IP asli client
- Response tetap stateful (TCP)

# IV. Trade-offs Analysis
## Pros:
- Solusi clean untuk overlapping CIDR
- High security (No direct VPC exposure)
- High security (No direct VPC exposure)
- Managed service & scalable

## Cons:
- Cost (NLB + Endpoint per AZ)
- Hanya consumer yang bisa initiate
- Hanya consumer yang bisa initiate
- Tidak untuk full mesh network

# V. Alternative Approach

## Alternatif:
- NAT Gateway / NAT Instance

## Analisis:
Pendekatan ini memungkinkan, namun:
- Lebih kompleks
- Kurang secure
- Tidak se-elegan PrivateLink

# 🏁 Kesimpulan
AWS PrivateLink memungkinkan komunikasi antar VPC tanpa bergantung pada routing berbasis CIDR.
Solusi ini:
- Mengatasi overlapping network
- Lebih secure
- Lebih scalable
- Sesuai standar arsitektur cloud modern

🚀 Final Insight

Solusi ini menggeser komunikasi dari network-level ke service-level,
yang merupakan prinsip utama dalam arsitektur cloud modern.
