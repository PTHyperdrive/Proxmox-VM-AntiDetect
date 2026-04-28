# proxmox-atd

**Proxmox VE Anti-Detection Toolkit** -- Make your virtual machines indistinguishable from physical hardware.

Built on top of [AICodo/pve-emu-realpc](https://github.com/AICodo/pve-emu-realpc), reengineered with a modular patcher, unified build pipeline, and user-configurable hardware profiles.

---

## What This Does

This toolkit patches three Proxmox components to defeat VM detection software:

| Component | What Gets Patched | Detection It Defeats |
|---|---|---|
| **QEMU/KVM** | Brand strings, SMBIOS tables, ACPI, IDE/SATA serials, PCI IDs, EDID, USB | pafish64, al-khaser, VMAware, CPUID checks |
| **EDK2/OVMF** | Firmware module names, UEFI identifiers | Firmware fingerprinting |
| **Kernel KVM** | RDTSC timing, hypervisor singlestep interception | Timing analysis, debugger detection |

---

## Quick Start

### Option A: Download Pre-Built Packages

1. Go to [Releases](../../releases) and download the latest `.deb` files + `.aml` files.
2. Upload them to your PVE server:
   ```bash
   scp pve-qemu-kvm_*.deb pve-edk2-firmware-ovmf_*.deb ssdt.aml ssdt-ec.aml hpet.aml root@YOUR_PVE_IP:/root/
   ```
3. Install on the PVE server:
   ```bash
   dpkg -i pve-qemu-kvm_*.deb
   dpkg -i pve-edk2-firmware-ovmf_*.deb
   ```
4. No reboot required.

### Option B: Build From Source

```bash
# On your PVE server (or a Debian build machine):
git clone https://github.com/YOUR_REPO/proxmox-atd.git
cd proxmox-atd

# Full build with default ASUS profile
sudo ./pve-build-orchestrator.sh --target all

# Or build just QEMU with a custom profile
sudo ./pve-build-orchestrator.sh --target qemu --profile profiles/example-intel-desktop.conf

# Artifacts will be in ./build-output/artifacts/
```

---

## Setup Guide

### Step 1: Prepare Your PVE Host

Before creating VMs, change the MAC address prefix in PVE:

```
PVE Web UI -> Datacenter -> Options -> MAC Address Prefix -> D8:FC:93
```

### Step 2: Install Packages

```bash
# Check your current QEMU version
dpkg -l | grep pve-qemu-kvm

# If already on v10.x, install directly
dpkg -i /root/pve-qemu-kvm_10.*_amd64.deb
dpkg -i /root/pve-edk2-firmware-ovmf_*.deb

# If on an older version, update first
apt update && apt install pve-qemu-kvm
dpkg -i /root/pve-qemu-kvm_10.*_amd64.deb
dpkg -i /root/pve-edk2-firmware-ovmf_*.deb
```

### Step 3: Create the VM

**Recommended hardware configuration:**

| Setting | Value | Why |
|---|---|---|
| BIOS | OVMF (UEFI) | Required for EFI anti-detection |
| Machine | Q35 | Modern chipset, less VM-like |
| CPU | host, 1 socket | Must be single socket |
| Cores | 4-16 | Match realistic hardware |
| Memory | 4096 / 8192 / 16384 | Only these sizes look real |
| Disk | SATA, 128GB+ | Avoid Virtio/SCSI |
| CD Drive | IDE or SATA | Avoid Virtio |
| Network | e1000 | Avoid VirtIO NIC |
| Display | Standard VGA | Then add GPU passthrough |
| Balloon | Disabled (0) | Real PCs don't have it |

**Avoid** all Virtio devices: SCSI disks, VirtIO NIC, VirtIO Block, VirtIO GPU.

### Step 4: Generate VM Configuration

Use the config generator to create an optimized `.conf` file:

```bash
# Generate and review
./tools/gen-vm-conf.sh --profile profiles/default.conf --vmid 102

# Write directly to PVE
sudo ./tools/gen-vm-conf.sh --profile profiles/default.conf --vmid 102 \
     --output /etc/pve/qemu-server/102.conf
```

Or manually edit the config:

```bash
nano /etc/pve/qemu-server/102.conf
```

**Example configuration (QEMU 9/10):**

```ini
args: -acpitable file=/root/ssdt.aml -acpitable file=/root/ssdt-ec.aml -acpitable file=/root/hpet.aml -cpu host,host-cache-info=on,hypervisor=off,vmware-cpuid-freq=false,enforce=false,host-phys-bits=true -smbios type=0,vendor="American Megatrends International LLC.",version=H3.7G,date='02/21/2023',release=3.7 -smbios type=1,manufacturer="ASUS",product="PRIME B760M-A",version="VER:H3.7G(2022/11/29)",serial="Default string",sku="Default string",family="Default string" -smbios type=2,manufacturer="ASUS",product="PRIME B760M-A",version="VER:H3.7G(2022/11/29)",serial="Default string",asset="Default string",location="Default string" -smbios type=3,manufacturer="Default string",version="Default string",serial="Default string",asset="Default string",sku="Default string" -smbios type=17,serial=DF1EC466,asset="9876543210" -smbios type=4,manufacturer="Intel(R) Corporation",version="12th Gen Intel(R) 0000" -smbios type=9 -smbios type=8 -smbios type=8
balloon: 0
bios: ovmf
boot: order=ide2;sata0;net0
cores: 8
cpu: host
memory: 16384
net0: e1000=D8:FC:93:XX:XX:XX,bridge=vmbr0,firewall=1
sata0: local:102/vm-102-disk-1.raw,size=128G,ssd=1,serial=0123456789ABCDEF0123
sockets: 1
```

### Step 5: Copy ACPI Tables

```bash
cp ssdt.aml ssdt-ec.aml hpet.aml /root/
```

### Step 6: Start the VM and Test

Install Windows in the VM, then run these detection tools:
- `pafish64.exe` (basic detection)
- `al-khaser` (advanced detection)
- [VMAware](https://github.com/kernelwernel/VMAware) (latest detection)
- CPU-Z, HWiNFO (hardware identity verification)

---

## Custom Hardware Profiles

Create your own hardware identity by editing a profile:

```bash
cp profiles/default.conf profiles/my-pc.conf
nano profiles/my-pc.conf
```

Key fields to customize:

```ini
[brand]
name=ASUS            # 4 uppercase chars, used everywhere

[smbios_type1]
manufacturer=ASUS    # What "System Manufacturer" shows
product=PRIME B760M-A # What "System Model" shows

[smbios_type4]
version=13th Gen Intel(R) Core(TM) i7-13700K  # CPU name

[smbios_type17]
memory_type=0x22     # 0x18=DDR4, 0x22=DDR5
speed=5600           # Memory clock speed
```

Both `.conf` (INI) and `.json` formats are supported -- pick whichever you prefer.

---

## Project Structure

```
proxmox-atd/
+-- atd-patcher.sh              # Main patcher engine
+-- pve-build-orchestrator.sh    # Unified build script
+-- CODING-STYLES.md             # Terminal output standards
+-- lib/
|   +-- atd-styles.sh            # Shared styling functions
+-- profiles/
|   +-- default.conf             # Default ASUS profile (INI)
|   +-- default.json             # Default ASUS profile (JSON)
|   +-- example-intel-desktop.*  # Example i7-13700K profile
+-- patches/
|   +-- qemu-brand.patch.sh      # QEMU brand string patches
|   +-- qemu-acpi.patch.sh       # ACPI table patches
|   +-- qemu-smbios.patch.sh     # SMBIOS hardware values
|   +-- qemu-ide-sata.patch.sh   # IDE/SATA serial/SMART
|   +-- qemu-usb-scsi.patch.sh   # USB/SCSI/SPD patches
|   +-- qemu-pci-ids.patch.sh    # PCI ID + GPU passthrough
|   +-- qemu-kvm-cpuid.patch.sh  # KVM CPUID signature
|   +-- qemu-misc.patch.sh       # File overlays
|   +-- edk2-brand.patch.sh      # EDK2/OVMF firmware patches
|   +-- kernel-rdtsc.patch.sh    # Kernel RDTSC interception
+-- tools/
|   +-- gen-vm-conf.sh           # VM config generator
+-- pve-emu-realpc-main/         # Original QEMU sources/assets
+-- pve-emu-realpc_edk2-*-main/  # Original EDK2 sources/assets
+-- pve-emu-realpc_kernel-main/  # Original kernel sources/patches
+-- .github/workflows/
    +-- unified-build.yml        # CI/CD pipeline
```

---

## Patcher Usage

The patcher supports dry-run mode, rollback, and per-target operation:

```bash
# Preview all changes (no files modified)
./atd-patcher.sh --dry-run --target qemu --qemu-dir ./pve-qemu/qemu

# Patch with custom profile
./atd-patcher.sh --profile profiles/my-pc.conf \
                 --target all \
                 --qemu-dir ./pve-qemu/qemu \
                 --edk2-dir ./pve-edk2-firmware/edk2 \
                 --kernel-dir ./pve-kernel/submodules/ubuntu-kernel

# Rollback patches
./atd-patcher.sh --rollback .atd-backup/20260428-153341
```

---

## Restoring Official Packages

To revert to stock Proxmox packages:

```bash
apt reinstall pve-qemu-kvm
apt reinstall pve-edk2-firmware-ovmf
```

---

## Known Limitations

- **Kernel modules** (`kvm-intel.ko`, `kvm-amd.ko`): The RDTSC interception
  kernel modules may cause visual latency and network issues. Use at your
  own discretion.
- **GPU passthrough** is recommended for passing GPU capability checks.
- Some VMAware checks require Windows registry cleanup -- see
  `tools/VMAware*.txt` for details.

---

## Credits

- [AICodo/pve-emu-realpc](https://github.com/AICodo/pve-emu-realpc) -- Original project
- [zhaodice/proxmox-ve-anti-detection](https://github.com/zhaodice/proxmox-ve-anti-detection) -- Reference implementation
