import Foundation

// Export rows — ports of the web accountExcelRows / personalExcelRows / incomeExcelRows /
// remindersChecksExcelRows / remindersPersonsExcelRows (same columns, order, totals and texts),
// plus a small XLSX writer (Office Open XML in a stored ZIP) so no external library is needed.

public enum ExportCell: Equatable, Sendable {
    case text(String)
    case number(Int)

    public var display: String {
        switch self {
        case .text(let s): return s
        case .number(let n): return Money.persianDigits(Money.format(n))
        }
    }
}

public struct DateRange: Equatable, Sendable {
    public var from: JalaliDate
    public var to: JalaliDate
    public init(from: JalaliDate, to: JalaliDate) { self.from = from; self.to = to }
    public func contains(_ d: JalaliDate) -> Bool { !(d < from) && !(to < d) }
}

public enum ExportBuilder {
    static let checkStatusLabel = ["pending": "در انتظار وصول", "cashed": "وصول شد", "bounced": "برگشت خورد", "cancelled": "باطل شد"]

    static func dateText(_ d: JalaliDate) -> String { Money.persianDigits("\(d.jy)/\(d.jm)/\(d.jd)") }

    /// web sort: date ascending, then entry time
    static func sorted(_ list: [JSONValue]) -> [JSONValue] {
        list.enumerated().sorted { a, b in
            let da = ImportAnalyzer.date(a.element["date"]), db = ImportAnalyzer.date(b.element["date"])
            if da != db { return da < db }
            let ta = a.element["ts"]?.intValue ?? 0, tb = b.element["ts"]?.intValue ?? 0
            if ta != tb { return ta < tb }
            return a.offset < b.offset
        }.map(\.element)
    }

    static func filter(_ list: [JSONValue], _ range: DateRange?, key: String = "date") -> [JSONValue] {
        guard let r = range else { return list }
        return list.filter { r.contains(ImportAnalyzer.date($0[key])) }
    }

    static func totalLine(_ n: Int, _ label: String, pad: Int, trailing: Int = 0) -> [ExportCell] {
        Array(repeating: .text(""), count: pad) + [.text(label), .text(Money.format(n) + " تومان"), .text(Money.format(n * 10) + " ریال")]
            + Array(repeating: .text(""), count: trailing)
    }

    public static func ledger(_ st: [String: JSONValue], accountId: String, range: DateRange?, includeLinked: Bool = true) -> [[ExportCell]] {
        var list = (st["expenses"]?.arrayValue ?? []).filter { $0["accountId"]?.idString == accountId }
        list = filter(list, range)
        if !includeLinked { list = list.filter { $0["linked"] == nil || ($0["linked"]?.isNull ?? false) } }
        var rows: [[ExportCell]] = [["تاریخ", "نوع", "دسته", "توضیحات", "مبلغ (تومان)", "مبلغ (ریال)"].map { .text($0) }]
        let s = sorted(list)
        for e in s {
            let t = ImportAnalyzer.toman(e)
            let linked = (e["linked"].map { !$0.isNull } ?? false) ? "🔗 " : ""
            rows.append([.text(dateText(ImportAnalyzer.date(e["date"]))), .text(e["type"]?.stringValue == "tankhah" ? "تنخواه" : "هزینه"),
                         .text(e["category"]?.stringValue ?? ""), .text(linked + (e["desc"]?.stringValue ?? "")), .number(t), .number(t * 10)])
        }
        let sum = s.filter { $0["type"]?.stringValue != "tankhah" }.reduce(0) { $0 + ImportAnalyzer.toman($1) }
        rows.append(totalLine(sum, "جمع کل هزینه‌ها", pad: 3))
        return rows
    }

    public static func personal(_ st: [String: JSONValue], range: DateRange?) -> [[ExportCell]] {
        let s = sorted(filter(st["personalExpenses"]?.arrayValue ?? [], range))
        var rows: [[ExportCell]] = [["تاریخ", "دسته", "توضیحات", "مبلغ (تومان)", "مبلغ (ریال)"].map { .text($0) }]
        for e in s {
            let t = ImportAnalyzer.toman(e)
            rows.append([.text(dateText(ImportAnalyzer.date(e["date"]))), .text(e["category"]?.stringValue ?? ""),
                         .text(e["desc"]?.stringValue ?? ""), .number(t), .number(t * 10)])
        }
        rows.append(totalLine(s.reduce(0) { $0 + ImportAnalyzer.toman($1) }, "جمع کل هزینه‌ها", pad: 2))
        return rows
    }

    public static func income(_ st: [String: JSONValue], range: DateRange?) -> [[ExportCell]] {
        let s = sorted(filter(st["incomes"]?.arrayValue ?? [], range))
        var rows: [[ExportCell]] = [["تاریخ", "نوع درآمد", "زیردسته", "اتصال", "توضیحات", "مبلغ (تومان)", "مبلغ (ریال)"].map { .text($0) }]
        for e in s {
            let t = ImportAnalyzer.toman(e)
            rows.append([.text(dateText(ImportAnalyzer.date(e["date"]))), .text(e["category"]?.stringValue ?? ""),
                         .text(e["subcategory"]?.stringValue ?? ""), .text(e["accountName"]?.stringValue ?? ""),
                         .text(e["desc"]?.stringValue ?? ""), .number(t), .number(t * 10)])
        }
        rows.append(totalLine(s.reduce(0) { $0 + ImportAnalyzer.toman($1) }, "جمع کل درآمد", pad: 4))
        return rows
    }

    public static func checks(_ st: [String: JSONValue], range: DateRange?) -> [[ExportCell]] {
        let list = filter(st["reminderChecks"]?.arrayValue ?? [], range, key: "dueDate").enumerated().sorted { a, b in
            let da = ImportAnalyzer.date(a.element["dueDate"]), db = ImportAnalyzer.date(b.element["dueDate"])
            return da != db ? da < db : a.offset < b.offset
        }.map(\.element)
        var rows: [[ExportCell]] = [["تاریخ سررسید", "شماره چک", "طرف حساب", "بانک", "دسته", "توضیحات", "مبلغ (تومان)", "مبلغ (ریال)", "وضعیت"].map { .text($0) }]
        var sum = 0
        for c in list {
            let a = c["amount"]?.intValue ?? 0
            sum += a
            let status = c["status"]?.stringValue ?? ""
            rows.append([.text(dateText(ImportAnalyzer.date(c["dueDate"]))), .text(Money.persianDigits(c["checkNumber"]?.idString ?? "")),
                         .text(c["party"]?.stringValue ?? ""), .text(c["bankName"]?.stringValue ?? ""), .text(c["category"]?.stringValue ?? ""),
                         .text(c["description"]?.stringValue ?? ""), .number(a), .number(a * 10), .text(checkStatusLabel[status] ?? status)])
        }
        rows.append(totalLine(sum, "جمع کل چک‌ها", pad: 5, trailing: 1))
        return rows
    }

    public static func persons(_ st: [String: JSONValue], range: DateRange?) -> [[ExportCell]] {
        var rows: [[ExportCell]] = [["نام", "نوع", "تاریخ سررسید قسط", "دسته", "توضیحات", "مبلغ (تومان)", "مبلغ (ریال)", "وضعیت"].map { .text($0) }]
        var sum = 0
        for p in st["reminderPersons"]?.arrayValue ?? [] {
            let insts = filter(p["installments"]?.arrayValue ?? [], range, key: "dueDate").enumerated().sorted { a, b in
                let da = ImportAnalyzer.date(a.element["dueDate"]), db = ImportAnalyzer.date(b.element["dueDate"])
                return da != db ? da < db : a.offset < b.offset
            }.map(\.element)
            if range != nil && insts.isEmpty { continue }
            for i in insts {
                let a = i["amount"]?.intValue ?? 0
                sum += a
                rows.append([.text(p["name"]?.stringValue ?? ""), .text(p["type"]?.stringValue == "creditor" ? "طلبکار" : "بدهکار"),
                             .text(dateText(ImportAnalyzer.date(i["dueDate"]))), .text(i["category"]?.stringValue ?? ""),
                             .text(i["description"]?.stringValue ?? ""), .number(a), .number(a * 10),
                             .text((i["paid"]?.isTruthy ?? false) ? "پرداخت‌شده" : "پرداخت‌نشده")])
            }
        }
        rows.append(totalLine(sum, "جمع کل اقساط", pad: 4, trailing: 1))
        return rows
    }

    /// web sanitizeSheetName
    public static func sheetName(_ name: String) -> String {
        let bad = Set("\\/?*[]:")
        let s = String(name.filter { !bad.contains($0) }.prefix(31))
        return s.isEmpty ? "Sheet" : s
    }
}

// MARK: - XLSX

public enum XLSXWriter {

    public static func make(sheets: [(name: String, rows: [[ExportCell]])]) -> Data {
        var files: [(String, Data)] = []
        let n = sheets.count
        var ct = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>"#
        for i in 1...max(1, n) {
            ct += #"<Override PartName="/xl/worksheets/sheet\#(i).xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>"#
        }
        ct += "</Types>"
        files.append(("[Content_Types].xml", Data(ct.utf8)))
        files.append(("_rels/.rels", Data(#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>"#.utf8)))

        var wb = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><bookViews><workbookView rightToLeft="1"/></bookViews><sheets>"#
        var rels = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#
        var used = Set<String>()
        for (i, s) in sheets.enumerated() {
            var name = ExportBuilder.sheetName(s.name)
            var k = 2
            while used.contains(name) { name = String(ExportBuilder.sheetName(s.name).prefix(28)) + " \(k)"; k += 1 }
            used.insert(name)
            wb += #"<sheet name="\#(esc(name))" sheetId="\#(i + 1)" r:id="rId\#(i + 1)"/>"#
            rels += #"<Relationship Id="rId\#(i + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet\#(i + 1).xml"/>"#
            files.append(("xl/worksheets/sheet\(i + 1).xml", Data(sheetXML(s.rows).utf8)))
        }
        rels += #"<Relationship Id="rId\#(n + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>"#
        wb += "</sheets></workbook>"
        files.append(("xl/workbook.xml", Data(wb.utf8)))
        files.append(("xl/_rels/workbook.xml.rels", Data(rels.utf8)))
        files.append(("xl/styles.xml", Data(#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="0"/><fonts count="2"><font><sz val="11"/><name val="Tahoma"/></font><font><b/><sz val="11"/><name val="Tahoma"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="3" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs></styleSheet>"#.utf8)))
        return Zip.store(files)
    }

    static func sheetXML(_ rows: [[ExportCell]]) -> String {
        let colCount = rows.map(\.count).max() ?? 1
        var widths = Array(repeating: 10, count: colCount)
        for r in rows { for (i, c) in r.enumerated() { widths[i] = min(60, max(widths[i], c.display.count + 2)) } }
        var x = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0" rightToLeft="1"/></sheetViews><cols>"#
        for (i, w) in widths.enumerated() { x += #"<col min="\#(i + 1)" max="\#(i + 1)" width="\#(w)" customWidth="1"/>"# }
        x += "</cols><sheetData>"
        for (ri, r) in rows.enumerated() {
            x += #"<row r="\#(ri + 1)">"#
            for (ci, c) in r.enumerated() {
                let ref = column(ci) + String(ri + 1)
                switch c {
                case .number(let n): x += #"<c r="\#(ref)" s="2"><v>\#(n)</v></c>"#
                case .text(let s):
                    if s.isEmpty { continue }
                    x += #"<c r="\#(ref)" t="inlineStr"\#(ri == 0 ? #" s="1""# : "")><is><t xml:space="preserve">\#(esc(s))</t></is></c>"#
                }
            }
            x += "</row>"
        }
        return x + "</sheetData></worksheet>"
    }

    static func column(_ i: Int) -> String {
        var n = i + 1, s = ""
        while n > 0 { let r = (n - 1) % 26; s = String(UnicodeScalar(UInt8(65 + r))) + s; n = (n - 1) / 26 }
        return s
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// Minimal ZIP writer (stored, no compression) with UTF-8 names.
public enum Zip {
    static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func crc32(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in d { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    public static func store(_ files: [(String, Data)]) -> Data {
        var out = Data()
        var central = Data()
        func u16(_ v: Int, _ d: inout Data) { var x = UInt16(truncatingIfNeeded: v).littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func u32(_ v: UInt32, _ d: inout Data) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        let dosTime = 0, dosDate = (2026 - 1980) << 9 | 1 << 5 | 1
        for (name, data) in files {
            let nameData = Data(name.utf8)
            let crc = crc32(data)
            let offset = UInt32(out.count)
            u32(0x04034b50, &out); u16(20, &out); u16(0x0800, &out); u16(0, &out); u16(dosTime, &out); u16(dosDate, &out)
            u32(crc, &out); u32(UInt32(data.count), &out); u32(UInt32(data.count), &out); u16(nameData.count, &out); u16(0, &out)
            out.append(nameData); out.append(data)
            u32(0x02014b50, &central); u16(20, &central); u16(20, &central); u16(0x0800, &central); u16(0, &central)
            u16(dosTime, &central); u16(dosDate, &central); u32(crc, &central); u32(UInt32(data.count), &central); u32(UInt32(data.count), &central)
            u16(nameData.count, &central); u16(0, &central); u16(0, &central); u16(0, &central); u16(0, &central); u32(0, &central)
            u32(offset, &central); central.append(nameData)
        }
        let cdOffset = UInt32(out.count)
        out.append(central)
        u32(0x06054b50, &out); u16(0, &out); u16(0, &out); u16(files.count, &out); u16(files.count, &out)
        u32(UInt32(central.count), &out); u32(cdOffset, &out); u16(0, &out)
        return out
    }
}
