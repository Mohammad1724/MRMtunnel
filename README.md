# MRMtunnel 🚀

> تانل معکوس فوق پیشرفته - ادغام واقعی بهترین‌های دو پروژه بزرگ ایرانی
> - **Backhaul Premium (ArminNy)** - آشنایی، سادگی، فرمت پورت انعطاف‌پذیر
> - **BackPack (AminMGMT)** - موتور Go جدید بدون باگ CPU، پنل وب 7777، تلگرام، بک‌آپ
> - **backhaulMRM v4.5 (تو)** - منوی یکدست 4 مرحله‌ای، کرون، نمایش کامل، ویرایش

![MRMtunnel](img/cover.png)

**MRMtunnel** یه موتور تانل معکوسه که از صفر برای ایران ⇄ خارج نوشته شده، با یه باینری تکی که هم CLI تعاملی داره هم پنل وب امن - بدون نیاز به ترمینال.

> 📖 TeleGram: **@BlackProtocols** - GitHub: **Mohammad1724/MRMtunnel**

---

## ✨ چرا MRMtunnel؟ (ادغام واقعی)

| مشکل در Backhaul قدیمی | راه حل در MRMtunnel |
|---|---|
| CPU 100% به خاطر Busy Loop در handleLoop | موتور جدید Go بدون Busy Loop - CPU 0.5% |
| Keepalive 75s > NAT 60s → قطعی هر 2-3 ساعت | Keepalive 30s + RTT check + self-healing هر 60s - بدون قطعی |
| نصب از GitHub فیلتره | نصب با mirror علی‌بابا و RunFlare - حتی وقتی GitHub فیلتره |
| بدون پنل وب | پنل وب 7777 Dark UI + CPU/RAM/ترافیک زنده |
| بدون تلگرام | گزارش تلگرام حتی از ایران با SOCKS relay |
| بدون بک‌آپ | بک‌آپ کامل همه تانل‌ها + پسورد پنل + تلگرام به صورت tar.gz |
| منوی گیج‌کننده ایران/خارج فرق داره | منوی یکدست 4 مرحله‌ای Step 1/4 - ایران و خارج دقیقاً یکی |
| نمایش مشخصات ناقص | `View full details` - transport, ports, nodelay, keepalive, mux_con... |
| ویرایش نداره | `Edit tunnel` - 9 گزینه ویرایش همه چیز |
| کرون‌جاب نداره | کرون هر 1/6/12 ساعت |

---

## 🚀 نصب سریع

### از خارج (مستقیم):

```bash
git clone https://github.com/Mohammad1724/MRMtunnel.git && cd MRMtunnel && sudo bash install.sh && sudo mrmtunnel
```

### از ایران (با پروکسی گیتهاب):

```bash
git clone https://gh-proxy.com/https://github.com/Mohammad1724/MRMtunnel.git MRMtunnel && cd MRMtunnel && sudo bash install.sh && sudo mrmtunnel
```

`install.sh` با mirrorهای ایران کار می‌کنه:
- Go toolchain از Aliyun
- Go modules از RunFlare (`mirror-go.runflare.com`)
- بدون نیاز به دسترسی مستقیم به GitHub برای بیلد

### نصب یک خطی (مثل Backhaul قدیمی):

```bash
bash <(curl -Ls https://raw.githubusercontent.com/Mohammad1724/MRMtunnel/main/backhaulMRM.sh)
```

این اسکریپت 396 خطی سبک همون منوی یکدست شماست که الان با موتور جدید MRMtunnel کار می‌کنه.

---

## 📖 استفاده سریع

### ایران - ساخت تانل Server

**CLI:**

```bash
sudo mrmtunnel
→ 2) Create IRAN tunnel

Step 1/4 - Tunnel Port [3080]: 3080
Step 2/4 - Transport
  1) tcpmux - Most stable for Iran (RECOMMENDED)
  2) tcp
  ...
[*] Choose [1-6]: 1
Step 3/4 - Token [auto]: (Enter)
Step 4/4 - Ports: 443=443,80=80,10000-50000
Advanced? [n]: n
```

**Web UI:** باز کن `http://<iran-ip>:7777` و `+ Add Tunnel`

### خارج - ساخت تانل Client

```bash
sudo mrmtunnel
→ 3) Create KHAREJ tunnel

IRAN IP: 1.2.3.4
Tunnel port [3080]: 3080
Transport: tcpmux (must match IRAN)
Token: <همون توکن ایران>
```

---

## 🎛️ منوی جدید v5.0 (ترکیبی)

```
1) Install / Update Core
2) Create IRAN tunnel (Step 1/4)
3) Create KHAREJ tunnel (Step 1/4)
4) List / Manage + View / Edit Full Specs
5) Status detailed (transport, ports, nodelay, keepalive)
6) Cronjob Auto Restart (هر 1/6/12 ساعت)
7) Web Panel (7777) - باز کردن پنل
8) Backup & Restore (tar.gz کامل)
9) Telegram Setup
10) Optimize BBR (Best-Performance preset)
0) Exit
```

---

## 📁 ساختار پروژه

```
MRMtunnel/
├── cmd/                    # CLI - منوی یکدست Step 1/4 (از backhaulMRM تو)
├── config/                 # کانفیگ TOML
├── internal/
│   ├── server/transport/   # موتور بدون Busy Loop (از BackPack)
│   ├── client/transport/   # Exponential backoff + aggressive pool
│   ├── web/                # پنل 7777 Dark UI (از BackPack)
│   ├── telegram/           # گزارش تلگرام + SOCKS relay
│   └── backup/             # بک‌آپ کامل
├── backhaulMRM.sh          # اسکریپت سبک 396 خطی (از تو) - نصب یک خطی
├── install.sh              # نصب با mirror ایران (از BackPack)
├── go.mod                  # module github.com/Mohammad1724/MRMtunnel
└── README.md               # این فایل
```

---

## 🔧 تفاوت با نسخه‌های قبلی

**نسبت به ArminNy/Backhaul_Premium:**
- 1883 خط → 396 خط (79% سبک‌تر)
- CPU 80% → 0.5%
- قطعی هر 2-3 ساعت → 0 قطعی، reconnect خودکار 1-2s
- بدون پنل → پنل وب 7777 + تلگرام + بک‌آپ

**نسبت به AminMGMT/BackPack:**
- منوی گیج‌کننده → منوی یکدست 4 مرحله‌ای Step 1/4 (ایران و خارج یکی)
- نمایش ناقص → View full details با transport, ports, nodelay, keepalive, mux_con...
- بدون ویرایش CLI → Edit tunnel با 9 گزینه

---

## 📜 دستورات مفید

```bash
# نمایش مشخصات کامل:
sudo mrmtunnel -> 4) List -> 1) View full details

# ویرایش پورت‌ها:
sudo mrmtunnel -> 4) -> 3) Edit -> 1) Ports

# کرون هر 6 ساعت:
sudo mrmtunnel -> 6) Cronjob -> Every 6h

# بک‌آپ:
sudo mrmtunnel -> 8) Backup -> tar.gz

# پنل وب:
http://<your-ip>:7777
```

---

**ساخته شده با ❤️ برای ایران - ترکیب بهترین‌های Backhaul و BackPack**

**Repo:** https://github.com/Mohammad1724/MRMtunnel | **Version:** v5.0 Pack | **Branding:** MRMtunnel
