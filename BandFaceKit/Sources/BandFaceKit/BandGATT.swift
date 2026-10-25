// SPDX-License-Identifier: MIT
//
// GATT браслета: сервіс FE95, запис у 0x005F без відповіді, сповіщення з 0x005E.

#if canImport(CoreBluetooth)
import CoreBluetooth

public enum BandGATT {
    public static let service = CBUUID(string: "FE95")
    /// Браслет → телефон (підписка на сповіщення).
    public static let rx = CBUUID(string: "0000005E-0000-1000-8000-00805F9B34FB")
    /// Телефон → браслет (запис без відповіді).
    public static let tx = CBUUID(string: "0000005F-0000-1000-8000-00805F9B34FB")
}
#endif
