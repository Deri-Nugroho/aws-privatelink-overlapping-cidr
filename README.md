# 🚀 AWS PrivateLink Solution: Overlapping CIDR Challenge

![AWS Architecture Diagram](assets/Overlapping_CIDR_VPC_Peering.drawio.png)

## 📌 Overview
Project ini mendokumentasikan implementasi **AWS PrivateLink** sebagai solusi teknis untuk mengatasi konflik routing pada VPC dengan CIDR identik (**VPC A & VPC C: 10.0.0.0/16**). Arsitektur ini mengadopsi prinsip **Zero Trust & Cost-Efficient**, memastikan layanan tetap terisolasi tanpa memerlukan Internet Gateway, NAT Gateway, maupun Public IP.

### 🌐 Network Topology
| Component | CIDR / Role | Function |
| :--- | :--- | :--- |
| **VPC A (Consumer)** | `10.0.0.0/16` | Client Environment (Overlapping) |
| **VPC C (Consumer)** | `10.0.0.0/16` | Client Environment (Overlapping) |
| **VPC B (Provider)** | `10.1.0.0/16` | Nginx Service Environment |

---

## 🎯 Key Takeaways
* **Overlapping Resolution:** PrivateLink menghindari ketergantungan pada routing Layer 3 (CIDR) ❌.
* **Layer 4 Communication:** Konektivitas berjalan di level TCP melalui AWS Backbone Network.
* **Service-Level Abstraction:** Fokus berpindah dari *network-peering* ke *service-access*.
* **Egress Control:** Menggunakan **S3 Gateway Endpoint** untuk manajemen paket OS tanpa biaya NAT Gateway.
* **Zero Inbound Management:** Akses terminal via **AWS Systems Manager (SSM)** tanpa membuka port 22 (SSH).

---

## 💡 Arsitektur Logic (The Golden Answer)
### ❓ Mengapa Tidak Terjadi Konflik Routing?
AWS PrivateLink bekerja di **Layer 4 (TCP)** dan tidak menggunakan tabel routing antar VPC.
1.  Setiap Consumer VPC memiliki **Interface Endpoint (ENI)** dengan IP lokal.
2.  Trafik diarahkan ke **Network Load Balancer (NLB)** di Provider VPC via internal AWS backbone.
3.  **Kesimpulan:** Karena tidak ada pertukaran rute CIDR antar VPC, konflik *overlapping* berhasil dieliminasi secara total.

---

## I. 🏗️ Persiapan Infrastruktur

### A. Provider (VPC B - 10.1.0.0/16)
1.  **VPC Setup:** Create `VPC-B-Provider`.
2.  **Subnet:** Private Subnet (AZ `us-east-1a`).
3.  **S3 Gateway Endpoint:** Associate ke Route Table VPC B agar EC2 bisa melakukan update package tanpa internet.

### B. Consumer (VPC A & VPC C - 10.0.0.0/16)
1.  **VPC Setup:** `VPC-A-Consumer` & `VPC-C-Consumer`.
2.  **DNS Settings:** Aktifkan **Enable DNS Hostnames** dan **Enable DNS Resolution** (Wajib untuk PrivateLink & SSM).
3.  **Subnet:** Private Subnet di AZ yang sama dengan Provider (`us-east-1a`).

---

## II. 🔐 Konfigurasi Security Groups
*Menerapkan prinsip Least Privilege (Hanya membuka port yang diperlukan).*

### A. Provider (VPC B)
* **SG-Nginx-Provider:**
    * **Inbound:** TCP 80 ← Source: `10.1.0.0/16`.
    * **Outbound:** HTTPS 443 → Destination: **S3 Prefix List ID**.

### B. Consumer (VPC A & C)
* **SG-EC2-Client:**
    * **Inbound:** `None`.
    * **Outbound:** TCP 443 → `SG-VPCE-SSM` | TCP 80 → `SG-VPCE-Privatelink`.
* **SG-VPCE-SSM:**
    * **Inbound:** TCP 443 ← Source: `SG-EC2-Client`.
* **SG-VPCE-Privatelink:**
    * **Inbound:** TCP 80 ← Source: `SG-EC2-Client`.

---

## III. ⚙️ Deployment Compute & Load Balancer

### A. Provider Side (VPC B)
1.  **EC2 Nginx Server:** IAM Role `AmazonSSMManagedInstanceCore`.
    * **User Data:**
        ```bash
        #!/bin/bash
        yum update -y
        yum install nginx -y
        systemctl start nginx
        systemctl enable nginx
        echo "<h1>Welcome to Nginx via PrivateLink</h1>" > /usr/share/nginx/html/index.html
        ```
2.  **Network Load Balancer (NLB):** Scheme: **Internal**. Listener: TCP 80 → Target Group: EC2 Nginx.

### B. Consumer Side (VPC A & C)
1.  **EC2 Client:** IAM Role `AmazonSSMManagedInstanceCore`. Gunakan `SG-EC2-Client`.

---

## IV. 🔗 Implementasi AWS PrivateLink

### A. Endpoint Service (Provider - VPC B)
1.  Hubungkan ke NLB yang telah dibuat.
2.  Enable: **Acceptance Required**.
3.  Catat **Service Name** (Contoh: `com.amazonaws.vpce.us-east-1.vpce-svc-xxxx`).

### B. Interface Endpoints (Consumer Side)
1.  **SSM Endpoints (3 Required per VPC):** `ssm`, `ssmmessages`, `ec2messages`.
    * **SG:** `SG-VPCE-SSM`.
    * **Setting:** **Enable Private DNS names: YES**.
2.  **Nginx Interface Endpoint:**
    * Category: **Other endpoint services**.
    * **Setting:** **Enable Private DNS names: NO** (Dikelola manual via Route 53).
    * **Subnet:** Pilih AZ yang sama dengan EC2 Client untuk performa optimal.

### C. DNS Mapping (Split-Horizon Strategy)
Menggunakan **Private Hosted Zone (PHZ)** terpisah untuk menangani domain yang sama di VPC berbeda:
1.  **VPC A:** Create PHZ `service.local` → Associate ke **VPC A**. Create Alias A Record `nginx` → Target: VPC A Endpoint DNS.
2.  **VPC C:** Create PHZ `service.local` (ID baru) → Associate ke **VPC C**. Create Alias A Record `nginx` → Target: VPC C Endpoint DNS.

---

## V. 🧪 Testing & Verification

1.  **Acceptance:** Pada VPC B, buka **Endpoint Connections** dan klik **Accept** untuk kedua koneksi Consumer.
2.  **Connectivity Test:** Masuk ke EC2 Client via SSM Session Manager.

# 1. DNS Resolution Check
```bash
nslookup nginx.service.local
```

# 2. Layer 4 Port Check
```bash
timeout 2 bash -c '</dev/tcp/nginx.service.local/80' && echo "PORT OPEN" || echo "PORT CLOSED"
```

# 3. HTTP Validation
```bash
curl -Iv http://nginx.service.local
```

# Expected Result: HTTP/1.1 200 OK.

## ⚖️ Trade-offs Analysis: PrivateLink vs. NAT Gateway + Peering

Dalam menangani *Overlapping CIDR*, terdapat dua pendekatan utama. Berikut adalah analisis perbandingan antara solusi **AWS PrivateLink** (Project ini) dengan solusi **NAT Gateway + VPC Peering** (Traditional SNAT):

### 🔄 Comparison Table

![AWS Architecture Diagram](assets/Challenge_Drop.png)

| Fitur | **AWS PrivateLink** (Our Solution) | **NAT Gateway + Peering** (Image Approach) |
| :--- | :--- | :--- |
| **Layer Komunikasi** | Layer 4 (TCP/Service-based) | Layer 3 (IP/Network-based) |
| **Konflik IP** | ✅ **None**. Tidak peduli jika CIDR sama. | ⚠️ **Managed via SNAT**. Butuh IP baru (172.16.x.x). |
| **Keamanan** | 🔒 **High**. Hanya expose port spesifik. | 🔐 **Medium**. Seluruh network terhubung. |
| **Biaya Fix (Hourly)** | 💰 **Low**. (Biaya per Interface Endpoint). | 💸 **High**. (Biaya per NAT Gateway per VPC). |
| **Kompleksitas Route** | 🟢 **Simple**. Tidak ada rute antar VPC. | 🔴 **Complex**. Route Table penuh dengan `pcx` target. |
| **Akses Internet** | ❌ **No**. Terisolasi total. | ✅ **Yes**. Client bisa keluar ke internet via NAT. |

---

### 🖼️ Deep Dive: Kenapa PrivateLink Lebih Unggul?

Berdasarkan arsitektur pada gambar "Friday Challenge" (NAT Gateway + Peering), terdapat beberapa kelemahan yang berhasil kita atasi dengan PrivateLink:

#### 1. Cost Efficiency (Optimization)
Pada solusi NAT Gateway, setiap VPC Consumer (VPC A & VPC C) harus membayar biaya sewa **NAT Gateway per jam** (~$0.045/jam) ditambah biaya data processing. 
* **PrivateLink:** Kita menghilangkan biaya NAT Gateway di sisi Consumer, yang secara signifikan mengurangi *monthly bill* perusahaan.

#### 2. Blast Radius & Security
Pada solusi Peering, jika satu EC2 di VPC A terkompromi, penyerang secara teori bisa memindai (scanning) seluruh network di VPC B karena jalur *routing* terbuka di level network.
* **PrivateLink:** Hanya **satu titik (Interface Endpoint)** dan **satu port (TCP 80)** yang terbuka. Penyerang tidak bisa melakukan *lateral movement* ke resource lain di VPC B.

#### 3. Operational Overhead
Pada solusi SNAT (Gambar), Admin jaringan harus mengelola "IP bayangan" (172.16.x.x) agar tidak bentrok. Jika ada 100 VPC Consumer, manajemen rute akan menjadi sangat *chaos*.
* **PrivateLink:** Skalabilitas hampir tak terbatas tanpa perlu memikirkan manajemen alamat IP tambahan.

---

## 🏁 Final Conclusion

Arsitektur **AWS PrivateLink** yang diimplementasikan dalam project ini merupakan solusi paling **Production-Grade** untuk menangani *Overlapping CIDR*. Ia mengeliminasi ketergantungan pada internet publik, menekan biaya operasional seminimal mungkin, dan memberikan tingkat keamanan tertinggi melalui isolasi level layanan (*Service-Level Isolation*).

> **Verdict:** "Traffic is not routed, but exposed as a service endpoint." — Inilah standar tertinggi dalam konektivitas antar-VPC di AWS.

## 🧠 Author Notes
Implementasi oleh Deri Nugroho. Berfokus pada:
- Cloud-Native Design
- Cost Optimization (Zero NAT Gateway cost)
- Security Engineering (Zero Trust & No SSH)
