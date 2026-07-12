// examples/time_scheduler — runnable demonstration of the `src/infra_time`
// + `src/infra_timer` directions as a cron-like maintenance-window
// workflow: parse RFC 3339 timestamps, do civil-calendar arithmetic, apply
// a POSIX TZ rule with DST, parse ISO 8601 durations, schedule timeouts on
// a hierarchical timer wheel, and dispatch jobs on a work-stealing
// scheduler.
//
// Run with:
//   moon run examples/time_scheduler

///|
fn main {
  println("=== 1. parse + format RFC 3339 / ISO 8601 ===")
  let dt = match @time.parse_iso8601("2026-07-12T18:30:00.250Z") {
    Some(d) => d
    None => {
      println("parse failed")
      return
    }
  }
  println("parsed      : \{dt}")
  println("iso8601     : \{@time.format_iso8601(dt)}")
  println("rfc2822     : \{@time.format_rfc2822(dt, 0)}")
  println("rfc3339 +08 : \{@time.format_rfc3339_with_offset(dt, 8 * 60)}")
  println("iso week    : \{@time.format_iso_week_date(dt)}")
  let pretty = @time.strftime(dt, "%a %b %e, %Y %H:%M:%S")
  println("strftime    : \{pretty}")
  println("")
  println("=== 2. civil-calendar arithmetic ===")
  let next_month = dt.add_months(1)
  println("+1 month    : \{@time.format_iso_date(next_month)}")
  let leap = @time.is_leap_year(2028)
  println(
    "2028 leap   : \{leap}, Feb 2028 has \{@time.days_in_month(2028, 2)} days",
  )
  let deadline = dt.add_days(45)
  println(
    "+45 days    : \{@time.format_iso_date(deadline)} (weekday \{deadline.weekday()})",
  )
  println("day of year : \{dt.day_of_year()}")
  println("")
  println("=== 3. POSIX TZ rule with DST (US Eastern) ===")
  match @time.parse_posix_tz("EST5EDT,M3.2.0/2,M11.1.0/2") {
    Some(rule) => {
      let (offset, name) = @time.tz_offset_at(rule, dt)
      println(
        "2026-07-12 UTC -> \{name} (offset \{offset / 3600}h), DST: \{@time.is_dst(rule, dt)}",
      )
      println(
        "local time  : \{@time.format_rfc3339_with_offset(dt, offset / 60)}",
      )
      let winter = match @time.parse_iso8601("2026-01-12T18:30:00Z") {
        Some(d) => d
        None => dt
      }
      let (woff, wname) = @time.tz_offset_at(rule, winter)
      println(
        "2026-01-12 UTC -> \{wname} (offset \{woff / 3600}h), DST: \{@time.is_dst(rule, winter)}",
      )
    }
    None => println("tz parse failed")
  }
  println("")
  println("=== 4. human-readable durations ===")
  match @time.parse_duration("2h30m") {
    Some(d) => {
      println(
        "2h30m       : \{d.total_minutes()} minutes (round-trip: \{d.to_string()})",
      )
      let ends = dt.add_duration(d)
      println("window ends : \{@time.format_iso8601(ends)}")
    }
    None => println("duration parse failed")
  }
  println("")
  println("=== 5. hierarchical timer wheel ===")
  let wheel = @timer.TimerWheel::new()
  let t_short = wheel.schedule(3)
  let t_mid = wheel.schedule(10)
  let t_cancel = wheel.schedule(5)
  println("scheduled 3 timers (ticks 3, 10, 5), pending = \{wheel.pending()}")
  println("cancel #\{t_cancel}: \{wheel.cancel(t_cancel)}")
  let mut fired_short = false
  let mut fired_mid = false
  for _tick in 0..<12 {
    let fired = wheel.advance()
    for id in fired {
      if id == t_short {
        fired_short = true
      }
      if id == t_mid {
        fired_mid = true
      }
    }
  }
  println(
    "after 12 ticks: short fired = \{fired_short}, mid fired = \{fired_mid}, pending = \{wheel.pending()}",
  )
  println("")
  println("=== 6. work-stealing scheduler ===")
  let ws = @timer.WorkStealingScheduler::new(4)
  // pile all work on worker 0 so idle workers must steal
  for i in 0..<16 {
    let _ = ws.submit(0, if i % 5 == 0 { 2 } else { 0 })
  }
  let executed = ws.run()
  println(
    "workers: \{ws.workers()}, executed \{executed.length()} tasks, steals: \{ws.steal_count()}",
  )
}
