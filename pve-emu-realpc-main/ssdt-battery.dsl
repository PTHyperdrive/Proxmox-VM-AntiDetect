/*
 * Intel ACPI Component Architecture
 * AML/ASL+ Disassembler version 20210930 (32-bit version)
 * Copyright (c) 2000 - 2021 Intel Corporation
 * 
 * Disassembling to symbolic ASL+ operators
 *
 * Disassembly of E:/Codes/Proxmox-VM-AntiDetect/pve-emu-realpc-main/ssdt-battery.aml, Tue Apr 28 23:35:30 2026
 *
 * Original Table Header:
 *     Signature        "SSDT"
 *     Length           0x0000087A (2170)
 *     Revision         0x02
 *     Checksum         0x0F
 *     OEM ID           "INTEL"
 *     OEM Table ID     "Ther_Rvp"
 *     OEM Revision     0x00000001 (1)
 *     Compiler ID      "INTL"
 *     Compiler Version 0x20250404 (539296772)
 */
DefinitionBlock ("", "SSDT", 2, "INTEL", "Ther_Rvp", 0x00000001)
{
    External (_SB_.PCI0, DeviceObj)

    Scope (_SB.PCI0)
    {
        Device (BAT0)
        {
            Name (_HID, EisaId ("PNP0C0A") /* Control Method Battery */)  // _HID: Hardware ID
            Name (_UID, Zero)  // _UID: Unique ID
            Name (_CID, "aicodoBAT")  // _CID: Compatible ID
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                Return (0x1F)
            }

            Method (_BIF, 0, NotSerialized)  // _BIF: Battery Information
            {
                Return (Package (0x0D)
                {
                    One, 
                    0x13BF, 
                    0x13BF, 
                    One, 
                    0x2EE0, 
                    0x0258, 
                    0x012C, 
                    0x3C, 
                    0x3C, 
                    "BAT0", 
                    "aicodo666", 
                    "LION", 
                    "aicodo"
                })
            }

            Method (_BST, 0, NotSerialized)  // _BST: Battery Status
            {
                Return (Package (0x04)
                {
                    Zero, 
                    Zero, 
                    0x13BF, 
                    0x2EE0
                })
            }
        }
    }

    Scope (\_TZ)
    {
        PowerResource (FN00, 0x00, 0x0000)
        {
            Method (_STA, 0, Serialized)  // _STA: Status
            {
                Local1 = 0x0F
                Return (Local1)
            }

            Method (_ON, 0, Serialized)  // _ON_: Power On
            {
            }

            Method (_OFF, 0, Serialized)  // _OFF: Power Off
            {
            }
        }

        Device (FAN0)
        {
            Name (_HID, EisaId ("PNP0C0B") /* Fan (Thermal Solution) */)  // _HID: Hardware ID
            Name (_UID, Zero)  // _UID: Unique ID
            Name (_CID, "CPU FAN")  // _CID: Compatible ID
            Name (_PR0, Package (0x01)  // _PR0: Power Resources for D0
            {
                FN00
            })
            Method (_FIF, 0, NotSerialized)  // _FIF: Fan Information
            {
                Return (Package (0x04)
                {
                    Zero, 
                    0x0A, 
                    0x08, 
                    0x80
                })
            }

            Method (_FST, 0, NotSerialized)  // _FST: Fan Status
            {
                Return (Package (0x03)
                {
                    Zero, 
                    0x32, 
                    0x00013880
                })
            }
        }

        PowerResource (FN01, 0x00, 0x0000)
        {
            Method (_STA, 0, Serialized)  // _STA: Status
            {
                Local1 = 0x0F
                Return (Local1)
            }

            Method (_ON, 0, Serialized)  // _ON_: Power On
            {
            }

            Method (_OFF, 0, Serialized)  // _OFF: Power Off
            {
            }
        }

        Device (FAN1)
        {
            Name (_HID, EisaId ("PNP0C0B") /* Fan (Thermal Solution) */)  // _HID: Hardware ID
            Name (_UID, One)  // _UID: Unique ID
            Name (_CID, "aicodoFAN-1")  // _CID: Compatible ID
            Name (_PR0, Package (0x01)  // _PR0: Power Resources for D0
            {
                FN01
            })
            Method (_FIF, 0, NotSerialized)  // _FIF: Fan Information
            {
                Return (Package (0x04)
                {
                    Zero, 
                    0x0A, 
                    0x08, 
                    0x80
                })
            }

            Method (_FST, 0, NotSerialized)  // _FST: Fan Status
            {
                Return (Package (0x03)
                {
                    Zero, 
                    0x32, 
                    0x00013880
                })
            }
        }

        PowerResource (FN02, 0x00, 0x0000)
        {
            Method (_STA, 0, Serialized)  // _STA: Status
            {
                Local1 = 0x0F
                Return (Local1)
            }

            Method (_ON, 0, Serialized)  // _ON_: Power On
            {
            }

            Method (_OFF, 0, Serialized)  // _OFF: Power Off
            {
            }
        }

        Device (FAN2)
        {
            Name (_HID, EisaId ("PNP0C0B") /* Fan (Thermal Solution) */)  // _HID: Hardware ID
            Name (_UID, 0x02)  // _UID: Unique ID
            Name (_CID, "aicodoFAN-2")  // _CID: Compatible ID
            Name (_PR0, Package (0x01)  // _PR0: Power Resources for D0
            {
                FN02
            })
            Method (_FIF, 0, NotSerialized)  // _FIF: Fan Information
            {
                Return (Package (0x04)
                {
                    Zero, 
                    0x0A, 
                    0x08, 
                    0x80
                })
            }

            Method (_FST, 0, NotSerialized)  // _FST: Fan Status
            {
                Return (Package (0x03)
                {
                    Zero, 
                    0x32, 
                    0x00013880
                })
            }
        }

        PowerResource (FN03, 0x00, 0x0000)
        {
            Method (_STA, 0, Serialized)  // _STA: Status
            {
                Local1 = 0x0F
                Return (Local1)
            }

            Method (_ON, 0, Serialized)  // _ON_: Power On
            {
            }

            Method (_OFF, 0, Serialized)  // _OFF: Power Off
            {
            }
        }

        Device (FAN3)
        {
            Name (_HID, EisaId ("PNP0C0B") /* Fan (Thermal Solution) */)  // _HID: Hardware ID
            Name (_UID, 0x03)  // _UID: Unique ID
            Name (_CID, "aicodoFAN-3")  // _CID: Compatible ID
            Name (_PR0, Package (0x01)  // _PR0: Power Resources for D0
            {
                FN03
            })
            Method (_FIF, 0, NotSerialized)  // _FIF: Fan Information
            {
                Return (Package (0x04)
                {
                    Zero, 
                    0x0A, 
                    0x08, 
                    0x80
                })
            }

            Method (_FST, 0, NotSerialized)  // _FST: Fan Status
            {
                Return (Package (0x03)
                {
                    Zero, 
                    0x32, 
                    0x00013880
                })
            }
        }

        PowerResource (FN04, 0x00, 0x0000)
        {
            Method (_STA, 0, Serialized)  // _STA: Status
            {
                Local1 = 0x0F
                Return (Local1)
            }

            Method (_ON, 0, Serialized)  // _ON_: Power On
            {
            }

            Method (_OFF, 0, Serialized)  // _OFF: Power Off
            {
            }
        }

        Device (FAN4)
        {
            Name (_HID, EisaId ("PNP0C0B") /* Fan (Thermal Solution) */)  // _HID: Hardware ID
            Name (_UID, 0x04)  // _UID: Unique ID
            Name (_CID, "aicodoFAN-4")  // _CID: Compatible ID
            Name (_PR0, Package (0x01)  // _PR0: Power Resources for D0
            {
                FN04
            })
            Method (_FIF, 0, NotSerialized)  // _FIF: Fan Information
            {
                Return (Package (0x04)
                {
                    Zero, 
                    0x0A, 
                    0x08, 
                    0x80
                })
            }

            Method (_FST, 0, NotSerialized)  // _FST: Fan Status
            {
                Return (Package (0x03)
                {
                    Zero, 
                    0x32, 
                    0x00013880
                })
            }
        }

        PowerResource (FN05, 0x00, 0x0000)
        {
            Method (_STA, 0, Serialized)  // _STA: Status
            {
                Local1 = 0x0F
                Return (Local1)
            }

            Method (_ON, 0, Serialized)  // _ON_: Power On
            {
            }

            Method (_OFF, 0, Serialized)  // _OFF: Power Off
            {
            }
        }

        Device (FAN5)
        {
            Name (_HID, EisaId ("PNP0C0B") /* Fan (Thermal Solution) */)  // _HID: Hardware ID
            Name (_UID, 0x05)  // _UID: Unique ID
            Name (_CID, "aicodoFAN-5")  // _CID: Compatible ID
            Name (_PR0, Package (0x01)  // _PR0: Power Resources for D0
            {
                FN05
            })
            Method (_FIF, 0, NotSerialized)  // _FIF: Fan Information
            {
                Return (Package (0x04)
                {
                    Zero, 
                    0x0A, 
                    0x08, 
                    0x80
                })
            }

            Method (_FST, 0, NotSerialized)  // _FST: Fan Status
            {
                Return (Package (0x03)
                {
                    Zero, 
                    0x32, 
                    0x00013880
                })
            }
        }

        ThermalZone (TZ00)
        {
            Method (_TMP, 0, NotSerialized)  // _TMP: Temperature
            {
                Return (0x0CE4)
            }

            Method (_MTL, 0, NotSerialized)  // _MTL: Minimum Throttle Limit
            {
                Return (0x64)
            }

            Method (_AC0, 0, NotSerialized)  // _ACx: Active Cooling, x=0-9
            {
                Return (0x0EA6)
            }

            Name (_AL0, Package (0x01)  // _ALx: Active List, x=0-9
            {
                FAN0
            })
            Name (_AL1, Package (0x01)  // _ALx: Active List, x=0-9
            {
                FAN1
            })
            Name (_AL2, Package (0x01)  // _ALx: Active List, x=0-9
            {
                FAN2
            })
            Name (_AL3, Package (0x01)  // _ALx: Active List, x=0-9
            {
                FAN3
            })
            Name (_AL4, Package (0x01)  // _ALx: Active List, x=0-9
            {
                FAN4
            })
            Name (_AL5, Package (0x01)  // _ALx: Active List, x=0-9
            {
                FAN5
            })
            Method (_PSV, 0, NotSerialized)  // _PSV: Passive Temperature
            {
                Return (0x0BB8)
            }

            Method (_HOT, 0, NotSerialized)  // _HOT: Hot Temperature
            {
                Return (0x0EA6)
            }

            Method (_CRT, 0, NotSerialized)  // _CRT: Critical Temperature
            {
                Return (0x0EA6)
            }

            Method (_SCP, 1, NotSerialized)  // _SCP: Set Cooling Policy
            {
            }

            Name (_TC1, 0x04)  // _TC1: Thermal Constant 1
            Name (_TC2, 0x03)  // _TC2: Thermal Constant 2
            Name (_TSP, 0x96)  // _TSP: Thermal Sampling Period
            Name (_TZP, Zero)  // _TZP: Thermal Zone Polling
            Name (_STR, Unicode ("System thermal zone"))  // _STR: Description String
        }

        ThermalZone (TZ01)
        {
            Method (_TMP, 0, NotSerialized)  // _TMP: Temperature
            {
                Return (0x0D84)
            }

            Method (_MTL, 0, NotSerialized)  // _MTL: Minimum Throttle Limit
            {
                Return (0x64)
            }

            Method (_AC0, 0, NotSerialized)  // _ACx: Active Cooling, x=0-9
            {
                Return (0x0EA6)
            }

            Method (_PSV, 0, NotSerialized)  // _PSV: Passive Temperature
            {
                Return (0x0BB8)
            }

            Method (_HOT, 0, NotSerialized)  // _HOT: Hot Temperature
            {
                Return (0x0EA6)
            }

            Method (_CRT, 0, NotSerialized)  // _CRT: Critical Temperature
            {
                Return (0x0EA6)
            }

            Method (_SCP, 1, NotSerialized)  // _SCP: Set Cooling Policy
            {
            }

            Name (_TC1, 0x04)  // _TC1: Thermal Constant 1
            Name (_TC2, 0x03)  // _TC2: Thermal Constant 2
            Name (_TSP, 0x96)  // _TSP: Thermal Sampling Period
            Name (_TZP, Zero)  // _TZP: Thermal Zone Polling
            Name (_STR, Unicode ("LM78A"))  // _STR: Description String
        }

        ThermalZone (TZ02)
        {
            Method (_TMP, 0, NotSerialized)  // _TMP: Temperature
            {
                Return (0x0C2C)
            }

            Method (_MTL, 0, NotSerialized)  // _MTL: Minimum Throttle Limit
            {
                Return (0x64)
            }

            Method (_AC0, 0, NotSerialized)  // _ACx: Active Cooling, x=0-9
            {
                Return (0x0EA6)
            }

            Method (_PSV, 0, NotSerialized)  // _PSV: Passive Temperature
            {
                Return (0x0BB8)
            }

            Method (_HOT, 0, NotSerialized)  // _HOT: Hot Temperature
            {
                Return (0x0EA6)
            }

            Method (_CRT, 0, NotSerialized)  // _CRT: Critical Temperature
            {
                Return (0x0EA6)
            }

            Method (_SCP, 1, NotSerialized)  // _SCP: Set Cooling Policy
            {
            }

            Name (_TC1, 0x04)  // _TC1: Thermal Constant 1
            Name (_TC2, 0x03)  // _TC2: Thermal Constant 2
            Name (_TSP, 0x96)  // _TSP: Thermal Sampling Period
            Name (_TZP, Zero)  // _TZP: Thermal Zone Polling
            Name (_STR, Unicode ("LM78A-1"))  // _STR: Description String
        }

        ThermalZone (TZ03)
        {
            Method (_TMP, 0, NotSerialized)  // _TMP: Temperature
            {
                Return (0x0C00)
            }

            Method (_MTL, 0, NotSerialized)  // _MTL: Minimum Throttle Limit
            {
                Return (0x64)
            }

            Method (_AC0, 0, NotSerialized)  // _ACx: Active Cooling, x=0-9
            {
                Return (0x0EA6)
            }

            Method (_PSV, 0, NotSerialized)  // _PSV: Passive Temperature
            {
                Return (0x0BB8)
            }

            Method (_HOT, 0, NotSerialized)  // _HOT: Hot Temperature
            {
                Return (0x0EA6)
            }

            Method (_CRT, 0, NotSerialized)  // _CRT: Critical Temperature
            {
                Return (0x0EA6)
            }

            Method (_SCP, 1, NotSerialized)  // _SCP: Set Cooling Policy
            {
            }

            Name (_TC1, 0x04)  // _TC1: Thermal Constant 1
            Name (_TC2, 0x03)  // _TC2: Thermal Constant 2
            Name (_TSP, 0x96)  // _TSP: Thermal Sampling Period
            Name (_TZP, Zero)  // _TZP: Thermal Zone Polling
            Name (_STR, Unicode ("aicodoTEMP-2"))  // _STR: Description String
        }

        ThermalZone (TZ04)
        {
            Method (_TMP, 0, NotSerialized)  // _TMP: Temperature
            {
                Return (0x0C0C)
            }

            Method (_MTL, 0, NotSerialized)  // _MTL: Minimum Throttle Limit
            {
                Return (0x64)
            }

            Method (_AC0, 0, NotSerialized)  // _ACx: Active Cooling, x=0-9
            {
                Return (0x0EA6)
            }

            Method (_PSV, 0, NotSerialized)  // _PSV: Passive Temperature
            {
                Return (0x0BB8)
            }

            Method (_HOT, 0, NotSerialized)  // _HOT: Hot Temperature
            {
                Return (0x0EA6)
            }

            Method (_CRT, 0, NotSerialized)  // _CRT: Critical Temperature
            {
                Return (0x0EA6)
            }

            Method (_SCP, 1, NotSerialized)  // _SCP: Set Cooling Policy
            {
            }

            Name (_TC1, 0x04)  // _TC1: Thermal Constant 1
            Name (_TC2, 0x03)  // _TC2: Thermal Constant 2
            Name (_TSP, 0x96)  // _TSP: Thermal Sampling Period
            Name (_TZP, Zero)  // _TZP: Thermal Zone Polling
            Name (_STR, Unicode ("aicodoTEMP-3"))  // _STR: Description String
        }

        ThermalZone (TZ05)
        {
            Method (_TMP, 0, NotSerialized)  // _TMP: Temperature
            {
                Return (0x0C10)
            }

            Method (_MTL, 0, NotSerialized)  // _MTL: Minimum Throttle Limit
            {
                Return (0x64)
            }

            Method (_AC0, 0, NotSerialized)  // _ACx: Active Cooling, x=0-9
            {
                Return (0x0EA6)
            }

            Method (_PSV, 0, NotSerialized)  // _PSV: Passive Temperature
            {
                Return (0x0BB8)
            }

            Method (_HOT, 0, NotSerialized)  // _HOT: Hot Temperature
            {
                Return (0x0DA6)
            }

            Method (_CRT, 0, NotSerialized)  // _CRT: Critical Temperature
            {
                Return (0x0EA6)
            }

            Method (_SCP, 1, NotSerialized)  // _SCP: Set Cooling Policy
            {
            }

            Name (_TC1, 0x04)  // _TC1: Thermal Constant 1
            Name (_TC2, 0x03)  // _TC2: Thermal Constant 2
            Name (_TSP, 0x96)  // _TSP: Thermal Sampling Period
            Name (_TZP, Zero)  // _TZP: Thermal Zone Polling
            Name (_STR, Unicode ("aicodoTEMP-4"))  // _STR: Description String
        }

        ThermalZone (TZ06)
        {
            Method (_TMP, 0, NotSerialized)  // _TMP: Temperature
            {
                Return (0x0C1C)
            }

            Method (_MTL, 0, NotSerialized)  // _MTL: Minimum Throttle Limit
            {
                Return (0x64)
            }

            Method (_AC0, 0, NotSerialized)  // _ACx: Active Cooling, x=0-9
            {
                Return (0x0EA6)
            }

            Method (_PSV, 0, NotSerialized)  // _PSV: Passive Temperature
            {
                Return (0x0BB8)
            }

            Method (_HOT, 0, NotSerialized)  // _HOT: Hot Temperature
            {
                Return (0x0EA6)
            }

            Method (_CRT, 0, NotSerialized)  // _CRT: Critical Temperature
            {
                Return (0x0EA6)
            }

            Method (_SCP, 1, NotSerialized)  // _SCP: Set Cooling Policy
            {
            }

            Name (_TC1, 0x04)  // _TC1: Thermal Constant 1
            Name (_TC2, 0x03)  // _TC2: Thermal Constant 2
            Name (_TSP, 0x96)  // _TSP: Thermal Sampling Period
            Name (_TZP, Zero)  // _TZP: Thermal Zone Polling
            Name (_STR, Unicode ("aicodoTEMP-5"))  // _STR: Description String
        }

        ThermalZone (TZ07)
        {
            Method (_TMP, 0, NotSerialized)  // _TMP: Temperature
            {
                Return (0x0C40)
            }

            Method (_MTL, 0, NotSerialized)  // _MTL: Minimum Throttle Limit
            {
                Return (0x64)
            }

            Method (_AC0, 0, NotSerialized)  // _ACx: Active Cooling, x=0-9
            {
                Return (0x0EA6)
            }

            Method (_PSV, 0, NotSerialized)  // _PSV: Passive Temperature
            {
                Return (0x0BB8)
            }

            Method (_HOT, 0, NotSerialized)  // _HOT: Hot Temperature
            {
                Return (0x0EA6)
            }

            Method (_CRT, 0, NotSerialized)  // _CRT: Critical Temperature
            {
                Return (0x0EA6)
            }

            Method (_SCP, 1, NotSerialized)  // _SCP: Set Cooling Policy
            {
            }

            Name (_TC1, 0x04)  // _TC1: Thermal Constant 1
            Name (_TC2, 0x03)  // _TC2: Thermal Constant 2
            Name (_TSP, 0x96)  // _TSP: Thermal Sampling Period
            Name (_TZP, Zero)  // _TZP: Thermal Zone Polling
            Name (_STR, Unicode ("aicodoTEMP-6"))  // _STR: Description String
        }
    }
}

