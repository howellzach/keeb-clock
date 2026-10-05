import Foundation

// Compare device wall-clock values in UTC so DST ambiguity does not normalize them.
func clockDate(_ record: [UInt8]) throws -> Date {
  guard record.count == 48 else { throw CidooCoreError.protocolError("Invalid config record length.") }
  var values: [Int] = []
  for (index, byte) in record[35..<42].enumerated() {
    if index == 3 { values.append(Int(byte)); continue }
    guard byte & 15 <= 9, byte >> 4 <= 9 else {
      throw CidooCoreError.protocolError("Invalid BCD clock field at byte \(35 + index).")
    }
    values.append(Int(byte >> 4) * 10 + Int(byte & 15))
  }
  let second = values[0], minute = values[1], hour = values[2]
  let weekday = values[3], day = values[4], month = values[5], year = 2000 + values[6]
  guard second < 60, minute < 60, hour < 24, weekday < 7,
    (1...31).contains(day), (1...12).contains(month) else {
    throw CidooCoreError.protocolError("Invalid config clock fields.")
  }
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  let components = DateComponents(year: year, month: month, day: day, hour: hour,
    minute: minute, second: second)
  guard let date = calendar.date(from: components) else {
    throw CidooCoreError.protocolError("Invalid clock date.")
  }
  let decoded = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
  guard decoded.year == year, decoded.month == month, decoded.day == day,
    decoded.hour == hour, decoded.minute == minute, decoded.second == second else {
    throw CidooCoreError.protocolError("Invalid config calendar date.")
  }
  return date
}

func verifyClockUpdate(before: [UInt8], requested: [UInt8], actual: [UInt8]) throws {
  guard before.count == 48, requested.count == 48, actual.count == 48 else {
    throw CidooCoreError.protocolError("Invalid config record length.")
  }
  for index in before.indices where !(35...41).contains(index) {
    guard before[index] == requested[index], before[index] == actual[index] else {
      throw CidooCoreError.protocolError("Non-clock configuration byte \(index) changed.")
    }
  }
  let actualDate = try clockDate(actual)
  let difference = actualDate.timeIntervalSince(try clockDate(requested))
  guard difference >= 0, difference <= 5 else {
    throw CidooCoreError.protocolError("Clock readback does not match the requested time.")
  }
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  guard Int(actual[38]) == calendar.component(.weekday, from: actualDate) - 1 else {
    throw CidooCoreError.protocolError("Clock readback weekday mismatch.")
  }
}
