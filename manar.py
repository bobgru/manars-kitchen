import random
import math
# import optimization
import sys
import os

# Worker menu
#    edit days off
#    edit capabilities
#    edit personal info

# Edit menu
#    manually add or remove assignment

# Allow editing of files by names?

# Add concept of week 1 vs. week 2

# Add worker sort order -- used in writing out assignments by worker
# Write out assignments by worker
#    add comment with worker name and station name(s)




def time_to_min(t):
  h = t / 100
  m = t % 100
  return h * 60 + m

# Su has index 0; Sa has index 6
days_of_week = ['Su','M','Tu','W','Th','F','Sa']

def day_to_dow(s):
  return days_of_week.index(s)

def cvt_run_to_days(r):
  if not r:
    return []
  ds = r.split('-')
  if len(ds) == 0:
    return []
  elif len(ds) == 1:
    return [day_to_dow(ds[0])]
  else:
    d1 = day_to_dow(ds[0])
    d2 = day_to_dow(ds[1])
    return range(d1, d2+1)

def unpack_days(ds):
  runs = ds.split(',')
  dows = map(cvt_run_to_days, runs)
  return flatten(dows)

def flatten(xss):
  ys = []
  for xs in xss:
    ys += xs
  return ys

class Station(object):
  def __init__(self, id, name, days, start_time, end_time, break_min):
    self.id         = id
    self.name       = name
    self.days       = days
    self.start_time = start_time
    self.end_time   = end_time
    self.break_min  = break_min

  def get_station_duration(self):
    st = time_to_min(self.start_time)
    et = time_to_min(self.end_time)
    if et < st:
      et += 24 * 60
    return et - st - self.break_min


# TODO use this to check prev and next days' assignments against a possible new one
# and compare result with minimum gap (constant: 8 hours?)
def get_station_gap_minutes(spair):
  s1 = spair[0]
  s2 = spair[1]
  st1 = time_to_min(s1.start_time)
  et1 = time_to_min(s1.end_time)
  if et1 < st1:
    et1 += 24 * 60

  st2 = time_to_min(s2.start_time)
  et2 = time_to_min(s2.end_time)
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


# add sorted list of station preferences
# usual rule: 5 days/wk, every other weekend off
# review hours
# regular days off
# add custom available -- days, hours
class Worker(object):
  def __init__(self, id, last_name, first_name, title, sort_order, hours_per_week, overtime_ok, fav_station, benefit_days, comp_days):
    self.id             = id       
    self.last_name      = last_name
    self.first_name     = first_name
    self.title          = title
    self.sort_order     = sort_order
    self.hours_per_week = hours_per_week
    self.overtime_ok    = overtime_ok
    self.fav_station    = fav_station
    self.benefit_days   = unpack_days(benefit_days)
    self.comp_days      = unpack_days(comp_days)

worker_data = [
( 1,"Dickinson", "Theron",             "1st Cook",            1, 40, False,  7, "", ""),
(54,"Joseph", "Nicole",                "1st Cook",            2, 40, False, 14, "", ""),
( 3,"Sales", "Geraldo",                "1st Cook",            3, 40, False,  9, "", ""),
( 4,"Carballo", "Fabio",               "2nd Cook",            4, 40, False,  1, "", ""),
(17,"Carreiro", "Marcos",              "2nd Cook",            5, 40, False,  6, "", ""),
( 5,"Chludzinska", "Marianna",         "2nd Cook",            6, 40, True,   8, "", ""),
( 6,"Lagrant", "Leroy",                "2nd Cook",            7, 40, True,  13, "", ""),
( 7,"Law", "Philip",                   "2nd Cook",            8, 40, True,   3, "", ""),
( 8,"Lefteri", "Fotaq",                "2nd Cook",            9, 40, False,  3, "", ""),
( 9,"Lejentus", "Rene",                "2nd Cook",           10, 20, False,  0, "", ""),

(10,"Marku", "Zef",                    "2nd Cook",           11, 20, True,   0, "", ""),
(65,"Mayorga", "Tezla",                "2nd Cook",           12, 40, False, 40, "", ""),
(11,"Moreno", "Osvaldo",               "2nd Cook",           13,  0, True,   0, "", ""),
(12,"Ortiz", "Angela",                 "2nd Cook",           14, 40, False,  6, "", ""),
(13,"Sokolowska", "Czeslawa",          "2nd Cook",           15, 40, True,   1, "", ""),
(14,"Vaz", "David",                    "2nd Cook",           16, 20, True,  33, "", ""),
(15,"Velazques", "Hoover",             "2nd Cook",           17, 40, True,  15, "", ""),
(16,"Williams", "Veniesa",             "2nd Cook",           18, 16, True,   2, "", ""),
# missing person here
(21,"Caddeus", "Winfred",              "1st Cook",           20, 40, True,  12, "", ""),

(22,"Elorch", "Omar",                  "1st Cook",           21, 40, False, 14, "", ""),
(18,"Diaz", "Ruben",                   "2nd Cook",           22, 40, False, 10, "", ""),
(19,"El Mouttaki", "Mohamed",          "2nd Cook",           23, 40, True,  15, "", ""),
(24,"Almeda", "Jose Marcel",           "Shift Lead",         24, 40, False, 16, "", ""),
(25,"Buckley", "John",                 "Shift Lead",         25, 40, False, 16, "", ""),
(23,"Portillo", "Jorge",               "1st Cook",           26, 40, True,  11, "", ""),
(59,"Vasconuelos", "Antonio",          "Shift Lead",         27, 32, True,  10, "", ""),
(27,"Millard", "Brian",                "Sous Chef",          28, 40, True,  16, "", ""),
(61,"Rocha", "Fabio",                  "Sous Chef",          29, 40, False, 40, "", ""),
(28,"Barros", "Deila",                 "Prod-Aide",          30, 40, True,  19, "", ""),

(62,"Briskaj", "Alketa",               "Prod-Aide",          31, 40, False, 40, "", ""),
(29,"Chodkowska", "Marzena",           "Prod-Aide",          32, 40, True,  20, "", ""),
(30,"Kozlowski", "Jadwiga",            "Prod-Aide",          33, 40, False,  0, "", ""),
(63,"Mehari", "Meaza",                 "Prod-Aide",          34, 40, False, 40, "", ""),
(31,"Samuel", "Willie James",          "Prod-Aide",          35, 40, True,  21, "", ""),
(32,"McCormack", "David",              "Material",           36, 40, False, 24, "", ""),
(60,"Selman", "Deric",                 "Prod-Aide",          37, 40, True,  18, "", ""),
(64,"Velasquez", "Jesus",              "Prod-Aide",          38, 40, False, 40, "", ""),
(33,"Fofana", "Abu",                   "Receiver",           39, 40, True,  26, "", ""),
(34,"Morano", "Juan",                  "Receiver",           40, 40, False, 25, "", ""),

(35,"Coren", "Gregorey",               "Sr. Material",       41, 40, False, 23, "", ""),
(36,"Cuthbert Jr", "Ezekiel",          "Supply Clerk",       42, 40, False, 27, "", ""),
(58,"Alby", "Taoufik",                 "2nd Cook",           43, 40, False, 40, "", ""),
(40,"Echavarria", "Fernando",          "2nd Cook",           44, 40, True,  39, "", ""),
(41,"Frontin", "Sheldon",              "2nd Cook",           45, 40, True,  38, "", ""),
(42,"Soriano", "Rene",                 "2nd Cook",           46, 40, False, 41, "", ""),
(43,"Cortell", "Glenn",                "2nd Cook",           47, 40, True,  36, "", ""),
(44,"Joseph", "Paul",                  "2nd Cook",           48, 40, False, 37, "", ""),
(45,"Pyskaty", "Maria",                "Prod-Aide",          49, 40, False, 38, "", ""),
(46,"Terron", "Maria",                 "Prod-Aide",          50, 40, False, 39, "", ""),

(47,"Campbell", "Trevon",              "Prod-Aide",          51, 40, True,  40, "", ""),
( 2,"Kanina", "Ewa",                   "1st Cook",           52, 40, False, 35, "", ""),
(57,"Almeida", "Anthony",              "2nd Cook",           53, 40, False, 32, "", ""),
(49,"Danial", "Clebert",               "2nd Cook",           54, 40, False,  0, "", ""),
(50,"Guevara", "Henry",                "2nd Cook",           55, 40, True,  30, "", ""),
(51,"Hines", "Michael",                "2nd Cook",           56, 40, True,   0, "", ""),
(52,"Murcia", "Alex",                  "2nd Cook",           57, 40, False, 28, "", ""),
(53,"Way", "Shon",                     "2nd Cook",           58, 40, False, 29, "", ""),
(55,"Bailey", "James",                 "2nd Cook",           59,  0, True,  36, "", ""),
(56,"Miller", "Edward",                "2nd Cook",           60,  0, True,  41, "", "")

]

workers = [Worker(int(d[0]), d[1], d[2], d[2], int(d[4]), int(d[5]), d[6], int(d[7]), d[8], d[9]) for d in worker_data]
worker_map = {}
for w in workers:
  worker_map[w.id] = w

class WorkerCapability(object):
  def __init__(self, worker_id, station_id):
    self.worker_id  = worker_id
    self.station_id = station_id

worker_capability_data = [
  # Theron
  (1, 7),

  # Nicole
  (54, 3), (54, 4), (54, 5), (54, 45),

  # Geraldo
  (3, 9),

  # Fabio C.
  (4, 1), (4, 2), (4, 6), (4, 8), 

  # Marcos
  (17, 1), (17, 2), (17, 6), (17, 8), (17, 10), (17, 11), (17, 19), (17, 20), (17, 21),

  # Marianna
  (5, 1), (5, 2), (5, 6), (5, 8),

  # Leroy
  (6, 3), (6, 4), (6, 5), (6, 12), (6, 13), (6, 14), (6, 15), (6, 35),

  # Philip
  (7, 3), (7, 7), (7, 9), (7, 14), (7, 15),

  # Fotaq
  (8, 1), (8, 2), (8, 3), (8, 4), (8, 5), (8, 6), (8, 7), (8, 8), (8, 9), 

  # Rene L.
  (9, 4), (9, 5),

  # Zef
  (10, 4), (10, 5),

  # Tezla

  # Osvaldo
  (11, 4), (11, 5),

  # Angela
  (12, 1), (12, 2), (12, 6), (12, 8),

  # Czeslawa
  (13, 1), (13, 2), (13, 6), (13, 8),

  # David V.
  (14, 3), (14, 4), (14,5), (14, 33),

  # Hoover
  (15, 1), (15, 2), (15, 3), (15, 4), (15, 5), (15, 6), (15, 7), (15, 8), (15, 9), 
    (15, 14), (15, 15),

  # Vaniesa
  (16, 1), (16, 2), (16, 3), (16, 4), (16, 5),
 
  # ???

  # Winfred
  (21, 10), (21, 11), (21, 12), (21, 13), (21, 35),

  # Omar
  (22, 15),

  # Ruben
  (18, 1), (18, 2), (18, 10), (18, 11), (18, 19), (18, 20), (18, 21),

  # Mohamed
  (19, 14), (19, 15), (19, 33),

  # Jose Marcel
  (24, 10), (24, 11), (24, 12), (24, 16), (24, 17), (24, 35), 

  # John B.
  (25, 10), (25, 16),

  # Jorge
  (23, 10), (23, 11), (23, 12), (23, 13), (23, 35),
    
  # Antonio
  (59, 10), (59, 13), (59, 14), (59, 15), (59, 16),

  # Brian
  (27, 10), (27, 11), (27, 16), (27, 17), (27, 47),
  
  # Fabio R.
  (61, 48),

  # Deila
  (28, 19), (28,20), (28, 21), (28, 22), (28, 42), (28, 43),

  # Alketa
  (62, 19), (62,20), (62, 21), (62, 22),

  # Marzena
  (29, 19), (29,20), (29, 21), (29, 22), (29, 42), (29, 43),

  # Jadwiga
  (30, 19), (30, 20), (30, 21), (30, 22),

  # Meaza
  (63, 19), (63, 20), (63, 21), (63, 22),

  # Willie James
  (31, 19), (31, 20), (31, 21), (31, 22),

  # David Mc.
  (32, 23), (32, 24), (32, 25), (32, 26), (32, 27),

  # Deric
  (60, 18), (60, 19), (60, 20), (60, 21), (60, 24), (60, 25), (60, 26), (60, 27), (60, 46),

  # Jesus
  (64, 46),

  # Abu
  (33, 26),

  # Juan
  (34, 25),

  # Gregorey
  (35, 23),

  # Zeke
  (36, 24), (36, 27),

  # Taoufik
  (58, 38), (58, 39), (58, 40), (58, 41),

  # Fernando
  (40, 38), (40, 39), (40, 40),

  # Sheldon
  (41, 38), (41, 39),

  # Rene S.
  (42, 32), (42, 34), (42, 41),

  # Glenn
  (43, 36), (43, 37),

  # Paul J.
  (44, 36), (44, 38),
  
  # Maria P.
  (45, 38), (45, 39), (45, 43),

  # Maria T.
  (46, 38), (46, 39), (46, 42),

  # Trevon
  (47, 40), (47, 44),

  # Ewa
  (2, 31), (2, 35),

  # Anthony
  (57, 32), (57, 33), (57, 34), (57, 38), (57, 39), (57, 40), (57, 41),

  # Clebert
  (49, 32), (49, 34),

  # Henry
  (50, 29), (50, 30), (50, 31), (50, 32), (50, 33),

  # Michael H.
  (51, 15), (51, 28), (51, 29), (51, 30), (51, 31), (51, 32), (51, 34),

  # Alex
  (52, 28),

  # Shon
  (53, 28), (53, 29),

  # James B.
  (55, 28), (55, 29), (55, 36), (55, 37), (55, 39),

  # Edward M.
  (56, 38), (56, 39), (56, 40), (56, 41)
 
]

worker_capabilities = [WorkerCapability(int(d[0]), int(d[1])) for d in worker_capability_data]

worker_stations_map  = {}
for w in workers:
  worker_stations_map[w.id] = []
for wc in worker_capabilities:
  sid = wc.station_id
  wid = wc.worker_id
  worker_stations_map[wid].append(sid)

station_workers_map = {}
for s in stations:
  station_workers_map[s.id] = []
for wc in worker_capabilities:
  sid = wc.station_id
  wid = wc.worker_id
  station_workers_map[sid].append(wid)

def find_station_by_id(sid):
  return station_map[sid]

def find_worker_by_id(wid):
  return worker_map[wid]

def get_assignment_display_text(wid):
  if wid < 0:
    return 'N/A'
  elif wid == 0:
    return '-'
  else:
    return find_worker_by_id(wid).last_name

def print_solution_by_tuple(sln):
  for x  in sln:
    sid = x[0]
    dow = x[1]
    wid = x[2]

    s = find_station_by_id(sid)
    d = days_of_week[dow]
    w = get_assignment_display_text(wid)
 
    print "%-10s %-2s %-10s" % (s.name, d, w)

# Assumes dow_stations are sorted by day of week.
def get_dow_station_display_text(w, dow_stations):
  stations_per_week = []
  minutes = 0
  for dow in range(len(days_of_week)):
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
        s = find_station_by_id(x[1])
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

# Assumes dow_workers are sorted by day of week.
def get_worker_display_text(dow_workers):
  workers_per_week = []
  for dow in range(len(days_of_week)):
    workers_per_day = []

    # Get all the workers for this day of the week.
    # Note: should be only 1
    for x in dow_workers:

      # If the next assignment is later in the week,
      # we're done with this day.
      if x[0] > dow:
        break

      # If we found an assignment for this day, include the name.
      if x[0] == dow:
        if x[1] < 0:
          workers_per_day.append('######')
        elif x[1] == 0:  
          workers_per_day.append('      ')
        else:
          w = find_worker_by_id(x[1])
          workers_per_day.append(w.last_name + ", " + w.first_name)

    # We have all the day's workers, so format them.
    if len(workers_per_day) > 0:
      workers_per_week.append("/".join(workers_per_day))
    else:
      workers_per_week.append("-")
  return " | ".join(workers_per_week)

# Print a compact human-readable week's schedule.
def print_stations_by_worker(sln):
  for w in workers:

    # Extract the assignments for this worker,
    # put day of week first, then sort them.
    dow_stations = [(x[1], x[0]) for x in sln if x[2] == w.id]
    dow_stations.sort(key=lambda tup: tup[0])
    # print dow_stations

    n = w.last_name + ", " + w.first_name
    t = get_dow_station_display_text(w, dow_stations)
    print "%-25s %-s" % (n, t)

# Print the weeks' assignments by station
def print_workers_by_station(sln):
  for s in stations:

    # Extract the workers for this station,
    # put day of week first, then sort them.
    dow_workers = [(x[1], x[2]) for x in sln if x[0] == s.id]
    dow_workers.sort(key=lambda tup: tup[0])

    n = s.name
    t = get_worker_display_text(dow_workers)
    print "%-20s | %-s |" % (n, t)


# Use 0 to indicate an open slot;
# -1 to indicate slot not available.
def get_empty_assignment(s, dow):
  day_ids = unpack_days(s.days)
  if dow in day_ids:
    return 0
  else:
    return -1


# A solution is a list of slots, where a slot is a triplet
# (station id, day of week, worker id).
#
# A worker id of 0 indicates an unassigned slot (there is no worker with id 0);
# -1 indicates an invalid slot (the station isn't open that day).
def make_empty_solution():
  sln = []
  for dow in range(len(days_of_week)):
    for s in stations:
      sln.append((s.id, dow, get_empty_assignment(s, dow)))
  return sln

empty_solution = make_empty_solution()

def find_slot_by_station_id_and_dow(sln, sid, dow):
  for slot in sln:
    if slot[0] == sid and slot[1] == dow:
      return slot
  print "Didn't find slot for station %d and dow %d" % (sid, dow)
  sys.exit 

def overlapping_times(s1, e1, s2, e2):
  # Sort the intervals so s1,e1 starts earlier in the day than s2,e2.
  if s1 > s2:
    # This statement swaps all the variables.
    s1, e1, s2, e2 = s2, e2, s1, e1
  # Deal with ending time past midnight. No starting time is past midnight.
  if e1 < s1:
    e1 += 2400
  return s2 < e1

def are_compatible_stations(sid1, sid2):
  s1 = find_station_by_id(sid1)
  s2 = find_station_by_id(sid2)
  return not overlapping_times(s1.start_time, s1.end_time, s2.start_time, s2.end_time)

def find_slots_by_worker_id_and_dow(sln, wid, dow):
  return [slot for slot in sln if slot[2] == wid and slot[1] == dow]

def valid_candidate(sln, sid, dow, wid):
  # If the worker has a benefit day or comp time, consider invalid.
  w = find_worker_by_id(wid)
  if dow in w.benefit_days:
    return False
  if dow in w.comp_days:
    return False

  # Get all the worker's assignments for the day.
  slots = find_slots_by_worker_id_and_dow(sln, wid, dow)
#  print "worker's current assignments for dow", wid, dow, slots

  # If there aren't any, the worker is a valid candidate.
  # If there are assignments, find conflicting ones. The worker is a
  # valid candidate if there are no conflicting assignments.
  bad_slots = [slot for slot in slots if not are_compatible_stations(sid, slot[0])]
#  print "bad_slots", bad_slots
  return len(bad_slots) == 0

def valid_candidate_no_overtime(sln, sid, dow, wid, worker_min):
  if valid_candidate(sln, sid, dow, wid):
    s = find_station_by_id(sid)
    m = worker_min + s.get_station_duration()
    return m <= 0
  else:
    return False

def choose_randomly_from_list(xs):
  if len(xs) == 0:
    return 0
  else:
    i = random.randint(0, len(xs) - 1)
    return xs[i]

# Return wid of candidate. Assumes station is open.
def choose_candidate_randomly(sln, slot, sid, dow, candidates_by_station):
  candidates = [wid for wid in candidates_by_station[sid]]
  return choose_randomly_from_list(candidates)

# Return wid of candidate. Assumes station is open.
def choose_candidate_randomly_no_conflicts(new_sln, slot, sid, dow, candidates_by_station):
  candidates = [wid for wid in candidates_by_station[sid]
                if valid_candidate(new_sln, sid, dow, wid)]
  return choose_randomly_from_list(candidates)

# Return wid of candidate. Assumes station is open.
def choose_candidate_randomly_no_overtime(sln, slot, sid, dow, candidates_by_station):
  worker_minutes = get_worker_minutes_in_schedule(sln)
  candidates = [wid for wid in candidates_by_station[sid]
                if valid_candidate_no_overtime(sln, sid, dow, wid, worker_minutes[wid])]
  return choose_randomly_from_list(candidates)

def tail(xs):
  ys = []
  for i in range(1, len(xs)):
    ys.append(xs[i])
  return ys

def calculate_gaps(sln, wid):
  # Get the worker's assignments.
  dow_stations = [(slot[1], slot[0]) for slot in sln if slot[2] == wid]

  # Sort by day of week then start_time.
  dow_stations.sort(key = lambda tup: tup[0] * 10000 + time_to_min(find_station_by_id(tup[1]).start_time))

  # Pair up successive assignments.
  pairs = zip(dow_stations, tail(dow_stations))

  # Discard pairs within same day.
  pairs2 = [p for p in pairs if p[0][0] != p[1][0]]

  # Extract stations from pairs.
  pairs3 = [(p[0][1], p[1][1]) for p in pairs2]

  # Compute the gaps between station pairs.
  gaps = map(get_station_gap_minutes, pairs3)

  return gaps

def get_worker_assignment_stats(sln, dow, wid):
  w = find_worker_by_id(wid)
  slots_week  = [slot for slot in sln if slot[2] == wid]
  slots_today = [slot for slot in sln if slot[2] == wid and slot[1] == dow]
  full_time = w.hours_per_week == 40
  minutes_week  = get_worker_minutes_in_schedule(slots_week)[wid]

  # HACK: adjust minutes_today by backing out the benefit days and hours per week
  minutes_today = get_worker_minutes_in_schedule(slots_today)[wid]
  minutes_today -= w.hours_per_week * 60 + len(w.benefit_days) * 8 * 60

  fav_station = w.fav_station
  return (wid, slots_week, full_time, minutes_week, minutes_today, fav_station)

def calculate_rank(full_time, minutes_week, minutes_today, same_assigment, first_choice, is_only_choice):
  rank = 0
  if not full_time:
    rank += 1
  if minutes_week > 0:
    rank += 1000 + minutes_week
  if minutes_today > 8 * 60:
    rank += 10000 + minutes_today
  if not same_assigment:
    rank += 300
  if not first_choice:
    rank += 100
  if not is_only_choice:
    rank += 500
  return rank

# Return wid of candidate. Assumes station is open.
def choose_candidate_ranked(sln, slot, sid, dow, candidates_by_station):
  s = find_station_by_id(sid)

  print
  print "station", sid, s.name
  print "day of week", dow, days_of_week[dow]
  print "candidates_by_station[sid]", candidates_by_station[sid]

  candidates = []
  for wid in candidates_by_station[sid]:
    
    print "considering worker", wid

    if valid_candidate(sln, sid, dow, wid):

      print "worker is valid candidate"

      stats = get_worker_assignment_stats(sln, dow, wid)

      print "worker stats"
      print "  wid", stats[0]
      print "  slots", stats[1]
      print "  full_time", stats[2]
      print "  minutes_week", stats[3]
      print "  minutes_today", stats[4]
      print "  fav_station", stats[5]

      # stats[0] = wid
      #      [1] = slots for wid in sln
      #      [2] = True if w is full time
      #      [3] = assigned minutes for w in sln 
      #      [4] = assigned minutes for w in sln for dow
      #      [5] = worker's favorite station
      same_assignment = len([slot for slot in stats[1] if slot[0] == sid]) > 0
      full_time = stats[2]
      minutes_week = stats[3] + s.get_station_duration()
      minutes_today = stats[4] + s.get_station_duration()
#       gaps = calculate_gaps(sln + [(sid, dow, wid)], wid)
#       small_gaps = [g for g in gaps if g < 8]
      is_first_choice = stats[5] == sid

      is_only_choice = len(candidates_by_station[sid]) == 1

      # If overtime and worker is not willing to do it, not a candidate.
      valid = True
      if minutes_week > 0:
        w = find_worker_by_id(wid)
        valid = w.overtime_ok

        if valid:
          print "worker willing to work overtime"
        else:
          print "worker not willing to work overtime"

#       if valid:
#         if small_gaps:
#           print "successive assignments too close together"
#           valid = False
#         else:
#           print "successive assignments OK"

      if valid:
        r = calculate_rank(full_time, minutes_week, minutes_today, same_assignment, is_first_choice, is_only_choice)
  
        print "full_time", full_time
        print "minutes_week", minutes_week
        print "minutes_today", minutes_today
        print "same_assignment", same_assignment
        print "is_first_choice", is_first_choice
        print "is_only_choice", is_only_choice
        print "rank",r
  
        candidates.append((r, wid))
  if len(candidates) == 0:

    print "no valid candidates"

    return 0
  else:

    print "candidates", candidates

    candidates.sort
    candidates.sort(key=lambda tup: tup[0])

    print "candidates, sorted", candidates

    return candidates[0][1]

# Copy a solution slot by slot to another one, updating
# the worker assignments by selecting a candidate using
# the supplied function.
def make_initial_solution(candidates_by_station, sln, choose_candidate):
  new_sln = [t for t in sln]
  for s in stations:
    for dow in range(len(days_of_week)):
      slot = find_slot_by_station_id_and_dow(new_sln, s.id, dow)
      if slot[2] == 0:
        new_slot = slot
        wid = choose_candidate(new_sln, slot, s.id, dow, candidates_by_station)
        if wid > 0:
          new_slot = (slot[0], slot[1], wid)
          ii = new_sln.index(slot)
          new_sln[ii] = new_slot
  return new_sln

def make_initial_solution_randomly(candidates_by_station, sln):
  return make_initial_solution(candidates_by_station, sln, choose_candidate_randomly)

def make_initial_solution_no_conflicts(candidates_by_station, sln):
  return make_initial_solution(candidates_by_station, sln, choose_candidate_randomly_no_conflicts)

def make_initial_solution_no_conflicts_or_overtime(candidates_by_station, sln):
  return make_initial_solution(candidates_by_station, sln, choose_candidate_randomly_no_overtime)

def make_initial_solution_ranked(candidates_by_station, sln):
  return make_initial_solution(candidates_by_station, sln, choose_candidate_ranked)


def assign_workers_to_only_capability(candidates_by_station, sln, choose_candidate):
  new_sln = [t for t in sln]
  for w in workers:
    slots = [slot for slot in sln if slot[2] == w.id]
    ss = worker_stations_map[w.id]
    if len(ss) == 1:
      s = find_station_by_id(ss[0])
      only_candidate = {}
      only_candidate[s.id] = [w.id]
      for dow in range(len(days_of_week)):
        slot = find_slot_by_station_id_and_dow(new_sln, s.id, dow)
        if slot[2] == 0:
          new_slot = slot
          wid = choose_candidate(new_sln, slot, s.id, dow, only_candidate)
          if wid > 0:
            new_slot = (slot[0], slot[1], wid)
            ii = new_sln.index(slot)
            new_sln[ii] = new_slot
  return new_sln


# Add the following:
#   open slots * 100000 
#   overtime hours * 10
def schedule_cost(sln):
  num_open_slots = sum([1 for slot in sln if slot[2] == 0])

  worker_minutes = get_worker_minutes_in_schedule(sln)
  overtime_minutes = 0
  for w in workers:
    if worker_minutes[w.id] > 0:
      overtime_minutes += worker_minutes[w.id]
  
  num_overtime_hours = overtime_minutes / 60 

  return num_open_slots * 100000 + num_overtime_hours * 10

# Return the total minutes assigned to each worker in the schedule,
# minus the worker's weekly maximum.  If the resulting value is
# negative, the worker has spare time; if zero, the worker is
# fully employed; if positive, the worker is scheduled overtime.
def get_worker_minutes_in_schedule(sln):
  worker_minutes = {}
  for w in workers:
    worker_minutes[w.id] = (-1) * w.hours_per_week * 60 + len(w.benefit_days) * 8 * 60

  for slot in sln:
    sid = slot[0]
    wid = slot[2]
    if wid > 0:
      s = find_station_by_id(sid)
      worker_minutes[wid] += s.get_station_duration()

  return worker_minutes
  
def print_overtime_workers(sln):
  worker_minutes = get_worker_minutes_in_schedule(sln)
  for w in workers:
    if worker_minutes[w.id] > 0:
      name = w.last_name + ", " + w.first_name
      print "%-24s %0.2f" % (name, worker_minutes[w.id]/60)

def print_undertime_workers(sln):
  worker_minutes = get_worker_minutes_in_schedule(sln)
  for w in workers:
    if worker_minutes[w.id] < 0:
      name = w.last_name + ", " + w.first_name
      print "%-24s %0.2f" % (name, worker_minutes[w.id]/60)


def total_contracted_hours():
  hours = map(lambda w: w.hours_per_week, workers)
  return sum(hours)

def total_station_hours():
  minutes = map(lambda s: s.get_station_duration() * len(unpack_days(s.days)), stations)
  return sum(minutes)/60

def format_slot_comment_for_file(slot):
  s = find_station_by_id(int(slot[0]))
  station_name = s.name

  day_name = days_of_week[int(slot[1])]

  wid = int(slot[2])
  worker_name = "OPEN"
  if wid > 0:
    w = find_worker_by_id(int(slot[2]))
    worker_name = "%s %s" % (w.first_name, w.last_name) 
 
  return "#%s,%s,%s\n" % (station_name, day_name, worker_name)


def rmdups(xs):
  seen = {}
  new_list = [seen.setdefault(x, x) for x in xs if x not in seen]
  return new_list

def format_worker_comment_for_file(wid, worker_assignments):
  # Prepare station data for comment
  sids = rmdups([int(slot[0]) for slot in worker_assignments])
  sids.sort()
  ss = []
  for sid in sids:
    s = find_station_by_id(sid)
    station_name = s.name
    ss.append("%1d=%s" % (sid, s.name))
  stations_comment = ", ".join(ss)
  w = find_worker_by_id(wid)
  worker_name = "%s %s" % (w.first_name, w.last_name) 
  return "# %s\n# %s\n" % (worker_name, stations_comment)


def format_slot_for_file(slot):
  return "%d,%d,%d\n" % slot

def save_solution(sln, f):
  text_file = open(f, "w")
  for slot in sln:
    if slot[2] >= 0:
      t = format_slot_comment_for_file(slot)
      text_file.write(t)
      t = format_slot_for_file(slot)
      text_file.write(t)
  text_file.close()

def save_solution_sorted_old(sln, f):
  text_file = open(f, "w")

  sorted_assignments = [(x[0], x[1], x[2]) for x in sln if x[2] > 0]
  sorted_assignments.sort(key=lambda tup: find_worker_by_id(tup[2]).sort_order * 100 + tup[1])
    
  for slot in sorted_assignments:
    t = format_slot_comment_for_file(slot)
    text_file.write(t)
    t = format_slot_for_file(slot)
    text_file.write(t)
  text_file.close()


def save_solution_sorted(sln, f):
  worker_assignment_map = {}
  for w in workers:
    sorted_assignments = [(x[0], x[1], x[2]) for x in sln if x[2] == w.id]
    sorted_assignments.sort(key=lambda tup: find_worker_by_id(tup[2]).sort_order * 100 + tup[1])
    worker_assignment_map[w.id] = sorted_assignments
    
  sorted_workers = [(w.id, w.sort_order) for w in workers]
  sorted_workers.sort(key=lambda tup: tup[1])

  text_file = open(f, "w")

  for wtup in sorted_workers:
    wid = wtup[0]
    was = worker_assignment_map[wid]
    t = format_worker_comment_for_file(wid, was)
    text_file.write(t)

    for slot in was:
      t = format_slot_for_file(slot)
      text_file.write(t)
    text_file.write("\n")

  text_file.close()


def read_solution(sln, f):
  new_sln = [slot for slot in sln]
  for line in file(f):
    if line.split() and not line.startswith("#"):
      sid, dow, wid = line.strip().split(',')
      sid = int(sid)
      dow = int(dow)
      wid = int(wid)
      sid_dow_slots = [slot for slot in new_sln if slot[0] == sid and slot[1] == dow]
      new_slot = (sid, dow, wid)
      if sid_dow_slots:
        ii = new_sln.index(sid_dow_slots[0])
        new_sln[ii] = new_slot
      else:
        print "Warning: could not find slot (%d,%d)" % (sid, dow)
        new_sln.append(new_slot)
  return new_sln

# print_solution_by_tuple(empty_solution)
# print(station_workers_map)
# initial_solution = make_initial_solution_randomly(station_workers_map, empty_solution)
# initial_solution = make_initial_solution_no_conflicts(station_workers_map, empty_solution)
# initial_solution = make_initial_solution_no_conflicts_or_overtime(station_workers_map, empty_solution)
# initial_solution = make_initial_solution_ranked(station_workers_map, empty_solution)

# solution_1 = assign_workers_to_only_capability(station_workers_map, empty_solution, choose_candidate_ranked)
# print
# print_stations_by_worker(solution_1)
# print
# print_workers_by_station(solution_1)
# 
# initial_solution = make_initial_solution_ranked(station_workers_map, solution_1)
# 
# 
# print
# print_stations_by_worker(initial_solution)
# print
# print_workers_by_station(initial_solution)
# print
# print "cost", schedule_cost(initial_solution)
# print
# print "overtime"
# print_overtime_workers(initial_solution)
# print
# print "undertime"
# print_undertime_workers(initial_solution)
# print
# print "total contracted hours", total_contracted_hours()
# print
# print "total station hours", total_station_hours()

# f = "worker_station_assignments.txt"
# print "Saving assignments to file", f
# save_solution(initial_solution, f)

# sln = read_solution(empty_solution, f)
# print_stations_by_worker(sln)

menu_actions = {}

solution = make_empty_solution()
last_assignments_file_saved  = ""
last_assignments_file_loaded = ""
last_assignments_file_update = ""

def do_menu_action():
  choice = raw_input(">> ")
  exec_menu(choice)

def select_filename(f):
  # TODO
  return f

def file_read_assignments():
  global solution
  global last_assignments_file_loaded

  if not last_assignments_file_loaded:
    last_assignments_file_loaded = "assignments.txt"
  f = select_filename(last_assignments_file_loaded)
  solution = read_solution(make_empty_solution(), f)
  print "The solution has been initialized from the file", last_assignments_file_loaded
  file_menu()

def file_update_assignments():
  global solution
  global last_assignments_file_update

  if not last_assignments_file_update:
    last_assignments_file_update = "assignments.txt"
  f = select_filename(last_assignments_file_update)
  solution = read_solution(solution, f)
  print "The solution has been updated from the file", last_assignments_file_update
  file_menu()

def file_write_assignments():
  global last_assignments_file_saved

  if not last_assignments_file_saved:
    last_assignments_file_saved = "assignments.txt"
  f = select_filename(last_assignments_file_saved)
  save_solution_sorted(solution, f)
  print "The solution has been saved to the file", last_assignments_file_saved
  file_menu()

def edit_clear_solution():
  global solution
  solution = make_empty_solution()
  print "The solution has been cleared of all assignments."
  edit_menu()

def edit_assign_stations_if_only_capability():
  global solution
  solution = assign_workers_to_only_capability(station_workers_map, solution, choose_candidate_ranked)
  print "Open stations have been assigned to workers with a single qualification."
  edit_menu()

def edit_assign_stations_by_rank():
  global solution
  solution = make_initial_solution_ranked(station_workers_map, solution)
  print "Open stations have been assigned to the highest ranking candidate."
  edit_menu()

def report_assignments_by_worker():
  print "Stations by Worker"
  print_stations_by_worker(solution)  
  reports_menu()

def report_assignments_by_station():
  print "Workers by Station"
  print_workers_by_station(solution)  
  reports_menu()

def report_overtime():
  print "Workers Scheduled Overtime"
  print_overtime_workers(solution)  
  reports_menu()

def report_undertime():
  print "Workers Scheduled Undertime"
  print_undertime_workers(solution)  
  reports_menu()


def main_menu():
  print "Enter the number of a command or submenu:"
  print "1. File menu"
  print "2. Edit menu"
  print "3. Options menu"
  print "4. Reports menu"
  print "\n0. Quit"
  do_menu_action()
  
def back():
  menu_actions['main_menu']()

def exec_menu(choice):
  os.system('clear')
  ch = choice.lower()
  if ch == '':
    back()
  else:
    try:
      menu_actions[ch]()
    except KeyError:
      print "Invalid selection, please try again.\n"
      back()
  return

def file_menu():
  print "File Menu"
  print
  print "11. Read assignments from file"
  print "12. Update assignments from file"
  print "13. Write assignments to file"
  print "9. Back"
  print "0. Quit"
  do_menu_action()

def edit_menu():
  print "Edit Menu"
  print
  print "21. Initialize assignments to empty"
  print "22. Assign open stations to workers with a single qualification"
  print "23. Assign open stations to highest-ranked candidate"
  print "9. Back"
  print "0. Quit"
  do_menu_action()

def options_menu():
  print "Options Menu"
  print
  print "9. Back"
  print "0. Quit"
  do_menu_action()

def reports_menu():
  print "Reports Menu"
  print
  print "41. All assignments by worker"
  print "42. All assignments by station"
  print "43. Overtime"
  print "44. Undertime"
  print "9. Back"
  print "0. Quit"
  do_menu_action()

def exit():
  sys.exit()
 
menu_actions = {
    'main_menu': main_menu
  , '0': exit
  , '9': back

  , '1': file_menu
  , '11': file_read_assignments
  , '12': file_update_assignments
  , '13': file_write_assignments

  , '2': edit_menu
  , '21': edit_clear_solution
  , '22': edit_assign_stations_if_only_capability
  , '23': edit_assign_stations_by_rank

  , '3': options_menu

  , '4': reports_menu
  , '41': report_assignments_by_worker
  , '42': report_assignments_by_station
  , '43': report_overtime
  , '44': report_undertime
}

if __name__ == "__main__":
  main_menu()

