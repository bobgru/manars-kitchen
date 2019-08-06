import time

class Station(object):
  def __init__(self, id, name, days, start_time, end_time, break_min):
    self.id         = id
    self.name       = name
    self.days       = days
    self.start_time = start_time
    self.end_time   = end_time
    self.break_min  = break_min

  def get_station_duration(self):
    st = time.time_to_min(self.start_time)
    et = time.time_to_min(self.end_time)
    if et < st:
      et += 24 * 60
    return et - st - self.break_min


# Use 0 to indicate an open slot;
# -1 to indicate slot not available.
def get_empty_assignment(s, dow):
  day_ids = time.unpack_days(s.days)
  if dow in day_ids:
    return 0
  else:
    return -1

# TODO use this to check prev and next days' assignments against a possible new one
# and compare result with minimum gap (constant: 8 hours?)
def get_station_gap_minutes(spair):
  s1 = spair[0]
  s2 = spair[1]
  st1 = time.time_to_min(s1.start_time)
  et1 = time.time_to_min(s1.end_time)
  if et1 < st1:
    et1 += 24 * 60

  st2 = time.time_to_min(s2.start_time)
  et2 = time.time_to_min(s2.end_time)
  if et2 < st2:
    et2 += 24 * 60

  if st1 > st2:
    st1, et1, st2, et2 = st2, et2, st1, et1

  return st2 - et1


station_data = [
( 1, "L2 AM",              "Su-Sa",        600,1430,30),
( 2, "L2 AM 2",            "Su-Sa",        600,1430,30),
( 3, "L2 Noon",            "Su-Sa",       1200,2030,30),
( 4, "L2 PM",              "Su-Sa",       1630,2030, 0),
( 5, "L2 PM 2",            "Su-Sa",       1630,2030, 0),
( 6, "CWN AM",             "Su-Sa",        600,1430,30),
( 7, "CWN PM",             "Su-Sa",       1230,2100,30),
( 8, "Shapiro AM",         "Su-Sa",        600,1430,30),
( 9, "Shapiro PM",         "Su-Sa",       1230,2100,30),
(10, "Production 1",       "Su-Sa",        500,1330,30),

(11, "Production 2",       "Su-Sa",        530,1400,30),
(12, "Production 3",       "M-F",          700,1530,30),
(13, "Production Prep",    "Su-Sa",        800,1630,30),
(14, "Production PM 1",    "Su-Sa",       1500,2330,30),
(15, "Production PM 2",    "Su-Sa",       1500,2330,30),
(16, "Shift Supervisor",   "Su-Sa",        500,1330,30),
(17, "Special",            "M-F",          700,1530,30),
(18, "Utility",            "M-F",          900,1730,30),
(19, "Salad AM 1",         "Su-Sa",        530,1400,30),
(20, "Salad AM 2",         "Su-Sa",        530,1400,30),

(21, "Salad AM 3",         "M-F",          600,1430,30),
(22, "Salad PM 1",         "Su-Sa",       1430,2300,30),
(23, "Receiver 1",         "M-F",          500,1330,30),
(24, "Receiver 2",         "M-F",          630,1500,30),
(25, "Receiver 3",         "M-F",          600,1430,30),
(26, "Receiver 4",         "Su-Th",        530,1400,30),
(27, "Receiver 5",         "Tu-Sa",        530,1400,30),
(28, "Grill AM 1",         "Su-Sa",        500,1330,30),
(29, "Grill AM 2",         "M-F",          530,1400,30),
(30, "Grill AM 3",         "M-F",         1030,1900,30),

(31, "Grill AM WE",        "Su,Sa",        700,1530,30),
(32, "Grill PM 1",         "M-F",         1600,  30,30),
(33, "Grill PM 2",         "Su-Sa",       1530,   0,30),
(34, "Grill PM WE",        "Su,Sa",       1530,   0,30),
(35, "Lead Cook Cafe",     "M-F",          700,1530,30),
(36, "Action 1",           "M-F",          600,1430,30),
(37, "Action 2",           "M-F",          700,1530,30),
(38, "Pizza AM 1",         "M-F",          530,1400,30),
(39, "Pizza AM 2",         "M-F",          700,1530,30),
(40, "Pizza AM WE",        "Su,Sa",        600,1430,30),

(41, "Pizza PM",           "Su-Sa",       1100,1930,30),
(42, "Deli 1",             "M-F",          530,1400,30),
(43, "Deli 2",             "M-F",          600,1430,30),
(44, "Deli 3",             "M-F",         1030,1900,30),
(45, "Project PM",         "M-F",         1200,1600, 0),
(46, "Support",            "Su-Sa",       1000,1830,30),
(47, "Sous Chef Brian",    "Su-Th",       1000,1830,30),
(48, "Sous Chef Fabio",    "Tu-Sa",       1000,1830,30)
]

stations = [Station(int(d[0]), d[1], d[2], int(d[3]), int(d[4]), int(d[5])) for d in station_data]
station_map = {}
for s in stations:
  station_map[s.id] = s

def find_station_by_id(sid):
  return station_map[sid]

def are_compatible_stations(sid1, sid2):
  s1 = find_station_by_id(sid1)
  s2 = find_station_by_id(sid2)
  return not time.overlapping_times(s1.start_time, s1.end_time, s2.start_time, s2.end_time)

def total_station_hours():
  minutes = map(lambda s: s.get_station_duration() * len(time.unpack_days(s.days)), stations)
  return sum(minutes)/60

# Assumes dow_stations are sorted by day of week.
def get_dow_station_display_text(w, dow_stations):
  stations_per_week = []
  minutes = 0
  for dow in range(len(time.days_of_week)):
    stations_per_day = []

    if dow in w.benefit_days:
      stations_per_week.append("Benefit Time")
      minutes += 8 * 60
      continue

    if dow in w.comp_days:
      stations_per_week.append("WC")
      minutes += 8 * 60
      continue

    # Get all the stations for this day of the week.
    for x in dow_stations:

      # If the next assignment is later in the week,
      # we're done with this day.
      if x[0] > dow:
        break

      # If we found an assignment for this day, include the name.
      if x[0] == dow:
        s = station.find_station_by_id(x[1])
        stations_per_day.append(s.name)
        minutes += s.get_station_duration()

    # We have all the day's stations, so format them.
    if len(stations_per_day) > 0:
      stations_per_week.append("/".join(stations_per_day))
    else:
      stations_per_week.append("OFF")
  t = ", ".join(stations_per_week)
  t += " | " + str(minutes / 60)
  return t

