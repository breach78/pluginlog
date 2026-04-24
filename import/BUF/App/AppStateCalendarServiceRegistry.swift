import Foundation

@MainActor
struct AppStateCalendarServiceRegistry {
  let scheduleCalendarService: any ScheduleCalendarServicing

  static func live(
    scheduleCalendarService: (any ScheduleCalendarServicing)? = nil
  ) -> AppStateCalendarServiceRegistry {
    AppStateCalendarServiceRegistry(
      scheduleCalendarService: scheduleCalendarService ?? ScheduleCalendarStore()
    )
  }
}
