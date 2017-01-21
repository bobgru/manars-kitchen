import random
import math
import optimization

def time_to_min(t):
  h = t / 100
  m = t % 100
  return h * 60 + m

class Station(object):
  def __init__(self, id, name, days, start_time, end_time, break_min):
    self.id         = id
    self.name       = name
    self.days       = days
    self.start_time = start_time
    self.end_time   = end_time
    self.break_min  = break_min

  def get_station_duration(self):
    st = self.start_time
    et = self.end_time
    if et < st:
      et += 2400
    st_min = time_to_min(st)
    et_min = time_to_min(et)
    return et_min - st_min - self.break_min

station_data = [
( 1, "CWN AM",             "Su-Sa",        600,1430,30),
( 2, "CWN PM",             "Su-Sa",       1230,2100,30),
( 3, "Project PM",         "M,Tu,Th,F",   1200,1600,30),
( 4, "L2 AM",              "Su-Sa",        600,1430,30),
( 5, "L2 AM 2",            "Su,Sa",        600,1430,30),
( 6, "L2 Noon",            "Su-Sa",       1200,2030,30),
( 7, "L2 PM",              "Su-Sa",       1630,2030,30),
( 8, "L2 PM 2",            "Su-Sa",       1630,2030,30),
( 9, "L2 Cafe Grill",      "Su,Sa",       1530,   0,30),
(10, "Shapiro AM",         "Su-Sa",        600,1430,30),
(11, "Shapiro PM",         "Su-Sa",       1230,2100,30),
(12, "Production",         "Su-Sa",        500,1330,30),
(13, "Production 1",       "Su-Sa",        530,1400,30),
(14, "Production 2",       "M-F",          700,1530,30),
(15, "Production Pre",     "Su-Sa",        800,1630,30),
(16, "Production PM",      "Su-Sa",       1500,2330,30),
(17, "Salad AM",           "Su-Sa",        600,1430,30),
(18, "New station 1",      "",             600,1430,30),
(19, "New station 2",      "",             600,1430,30),
(20, "Salad AM 2",         "Su-Sa",        600,1430,30),
(21, "Salad PM 1",         "Su-Sa",       1430,2300,30),
(22, "Salad PM 2",         "Su-Th",       1430,2300,30),
(23, "Grill AM 1",         "Su-Sa",        500,1330,30),
(24, "Grill AM 2",         "M-F",          530,1400,30),
(25, "Grill PM 1",         "M-F",         1630,  30,30),
(26, "Grill PM 2",         "M-F",         1800,   0,30),
(27, "Grill PM WE",        "Su,Sa",       1530,   0,30),
(28, "Grill 3",            "M-F",         1030,1900,30),
(29, "AM Cafe",            "M-F",          700,1530,30),
(30, "AM Cafe WE",         "Su,Sa",        700,1530,30),
(31, "S.A",                "M-F",          700,1530,30),
(32, "Shift Supe 1",       "Su-Tu,Th-Sa",  500,1330,30),
(33, "Receiver I",         "Su-Sa",        530,1400,30),
(34, "Receiver II",        "M-F",          600,1430,30),
(35, "Receiver III",       "M-F",          630,1500,30),
(36, "Receiver IIII",      "M-F",          500,1330,30),
(37, "Pizza AM WE",        "Su,Sa",        600,1430,30),
(38, "Pizza AM 1",         "M-F",          530,1400,30),
(39, "Pizza AM 2",         "M-F",          700,1530,30),
(40, "Pizza PM",           "M-F",         1100,1930,30),
(41, "Pizza PM WE",        "Su,Sa",       1130,2000,30),
(42, "Action 1",           "M-F",          600,1430,30),
(43, "Action 2",           "M-F",          700,1530,30),
(44, "Deli 1",             "Su,M,W-F",     530,1400,30),
(45, "Deli 2",             "M-Th,Sa",      600,1430,30),
(46, "Deli 3",             "M-F",         1030,1900,30)
]

stations = [Station(int(d[0]), d[1], d[2], int(d[3]), int(d[4]), int(d[5])) for d in station_data]
station_map = {}
for s in stations:
  station_map[s.id] = s

class Worker(object):
  def __init__(self, id, last_name, first_name, title, hours_per_week):
    self.id             = id       
    self.last_name      = last_name
    self.first_name     = first_name
    self.title          = title
    self.hours_per_week = hours_per_week

worker_data = [
( 1,"Dickinson", "Theron",             "1st Cook",           40),
( 2,"Kanina", "Ewa",                   "1st Cook",           40),
( 3,"Sales", "Geraldo",                "1st Cook",           40),
( 4,"Carballo", "Fabio",               "2nd Cook",           40),
( 5,"Chludzinska", "Marianna",         "2nd Cook",           40),
( 6,"Lagrant", "Leroy",                "2nd Cook",           24),
( 7,"Law", "Philip",                   "2nd Cook",           40),
( 8,"Lefteri", "Fotaq",                "2nd Cook",           40),
( 9,"Lejentus", "Rene",                "2nd Cook",           20),
(10,"Marku", "Zef",                    "2nd Cook",           20),
(11,"Moreno", "Osvaldo",               "2nd Cook",            8),
(12,"Ortiz", "Angela",                 "2nd Cook",           40),
(13,"Sokolowska", "Czeslawa",          "2nd Cook",           40),
(14,"Vaz", "David",                    "2nd Cook",           16),
(15,"Velazques", "Hoover",             "2nd Cook",           40),
(16,"Williams", "Veniesa",             "2nd Cook",           32),
(17,"Carreiro", "Marcos",              "2nd Cook",           40),
(18,"Diaz", "Ruben",                   "2nd Cook",           40),
(19,"El Mouttaki", "Mohamed",          "2nd Cook",           40),
(20,"Silien", "Jean",                  "2nd Cook",           40),
(21,"Caddeus", "Winfred",              "1st Cook",           40),
(22,"Elorch", "Omar",                  "1st Cook",           40),
(23,"Portillo", "Jorge",               "1st Cook",           40),
(24,"Almeda", "Jose Marcel",           "Shift Lead",         40),
(25,"Buckley", "John",                 "Shift Lead",         40),
(26,"Keefe", "John",                   "Shift Lead",         40),
(27,"Millard", "Brian",                "Shift Lead",         40),
(28,"Barros", "Deila",                 "Prod-Aide",          40),
(29,"Chodkowska", "Marzena",           "Prod-Aide",          40),
(30,"Kozlowski", "Jadwiga",            "Prod-Aide",           0),
(31,"Samuel", "Willie James",          "Prod-Aide",          40),
(32,"McCormack", "David",              "Material",           40),
(33,"Fofana", "Abu",                   "Receiver",           40),
(34,"Morano", "Juan",                  "Receiver",           40),
(35,"Coren", "Gregorey",               "Sr. Material",       40),
(36,"Cuthbert Jr", "Ezekiel",          "Supply Clerk",       40),
(37,"Espinoza", "Alene",               "Temp",               16),
(38,"Jones", "Dewanda",                "Temp",               40),
(39,"Virella", "Natalie",              "Temp",               40),
(40,"Echavarria", "Fernando",          "2nd Cook",           40),
(41,"Frontin", "Sheldon",              "2nd Cook",           40),
(42,"Sorino", "Rene",                  "2nd Cook",           40),
(43,"Cortell", "Glenn",                "2nd Cook",           40),
(44,"Joseph", "Paul",                  "2nd Cook",           40),
(45,"Pyskaty", "Maria",                "Prod-Aide",          40),
(46,"Terron", "Maria",                 "Prod-Aide",          40),
(47,"Campbell", "Trevon",              "Prod-Aide",          40),
(48,"Kamel", "(Temp)",                 "2nd Cook",           30),
(49,"Danial", "Clebert",               "2nd Cook",           40),
(50,"Guevara", "Henry",                "2nd Cook",           40),
(51,"Hines", "Michael",                "2nd Cook",           40),
(52,"Murcia", "Alex",                  "2nd Cook",           40),
(53,"Way", "Shon",                     "2nd Cook",           40),
(54,"Joseph", "Nicole",                "1st Cook",           40),
(55,"Bailey", "James",                 "2nd Cook",            8),
(56,"Miller", "Edward",                "2nd Cook",           40)
]

workers = [Worker(int(d[0]), d[1], d[2], d[2], int(d[4])) for d in worker_data]
worker_map = {}
for w in workers:
  worker_map[w.id] = w

class WorkerCapability(object):
  def __init__(self, worker_id, station_id):
    self.worker_id  = worker_id
    self.station_id = station_id

worker_capability_data = [
  # Line cooks
  (1, 1), (1, 2),
  (2, 3), (2, 4), (2,5), (2, 6), (2, 7), (2, 8),
  (3, 10), (3, 11),
  (4, 4), (4,5), (4, 6), (4, 7), (4, 8), 
  (5, 10), (5, 11),
  (6, 12), (6, 13), (6, 14), (6, 15), (6, 16),
  (7, 4), (7,5), (7, 6), (7, 7), (7, 8), (7, 10), (7, 11),
  (8, 1), (8, 2), (8, 3), (8, 4), (8,5), (8, 6), (8, 7), (8, 8), (8, 10), (8, 11),
  (9, 4), (9,5), (9, 6), (9, 7), (9, 8), 
  (10, 1), (10, 2), (10, 4), (10,5), (10, 6), (10, 7), (10, 8), (10, 10), (10, 11),
  (11, 4), (11,5), (11, 6), (11, 7), (11, 8), 
  (12, 1), (12, 2), (12, 4), (12,5), (12, 6), (12, 7), (12, 8), (12, 10), (12, 11),
  (13, 4), (13,5), (13, 6), (13, 7), (13, 8), (13, 10), (13, 11), 
    (13, 17), (13,18), (13, 19), (13, 20), (13, 21), (13, 22),
  (14, 4), (14,5), (14, 6), (14, 7), (14, 8), 
  (15, 4), (15,5), (15, 6), (15, 7), (15, 8),
    (15, 10), (15,11), (15, 12), (15, 13), (15, 14), (15, 15), (15, 16), 
  (16, 4), (16,5), (16, 6), (16, 7), (16, 8), 
 
  # Production cooks
  (17, 1), (17, 2), (17, 9),
    (17, 23), (17, 24), (17, 25), (17, 26), (17, 27), (17, 28),
  (18, 12), (18, 13), (18, 14), (18, 15), (18, 16),
    (18, 17), (18,18), (18, 19), (18, 20), (18, 21), (18, 22),
  (19, 12), (19, 13), (19, 14), (19, 15), (19, 16),
  (20, 12), (20, 13), (20, 14), (20, 15), (20, 16),
  (21, 12), (21, 13), (21, 14), (21, 15), (21, 16),
    (21, 23), (21, 24), (21, 25), (21, 26), (21, 27), (21, 28), (21, 29), (21, 30),
  (22, 12), (22, 13), (22, 14), (22, 15), (22, 16),
  (23, 12), (23, 13), (23, 14), (23, 15), (23, 16),
    
  # Shift-Leads cooks
  (24, 31), (24, 32), 
  (25, 12), (25, 13), (25, 14), (25, 15), (25, 16), (25, 31), (25, 32), 
  (26, 12), (26, 13), (26, 14), (26, 15), (26, 16), (26, 31), (26, 32), 
  (27, 12), (27, 13), (27, 14), (27, 15), (27, 16), (27, 31), (27, 32), 
  
  # Production Aides
  (28, 17), (28,18), (28, 19), (28, 20), (28, 21), (28, 22),
  (29, 17), (29,18), (29, 19), (29, 20), (29, 21), (29, 22),
  (30, 17), (30,18), (30, 19), (30, 20), (30, 21), (30, 22),
  (31, 17), (31,18), (31, 19), (31, 20), (31, 21), (31, 22),

  # Receiving
  (32, 33), (32, 34), (32, 35), (32, 36),
  (33, 33), (33, 34), (33, 35), (33, 36),
  (34, 33), (34, 34), (34, 35), (34, 36),
  (35, 33), (35, 34), (35, 35), (35, 36),
  (36, 33), (36, 34), (36, 35), (36, 36),

  # Temps
  (37, 17), (37,18), (37, 19), (37, 20), (37, 21), (37, 22),
  (38, 17), (38,18), (38, 19), (38, 20), (38, 21), (38, 22),
  (39, 17), (39,18), (39, 19), (39, 20), (39, 21), (39, 22),

  # Pizza
  (40, 23), (40, 24), (40, 25), (40, 26), (40, 27), (40, 28),
    (40, 37), (40, 38), (40, 39), (40, 40), (40, 41),
  (41, 23), (41, 24), (41, 25), (41, 26), (41, 27), (41, 28),
    (41, 37), (41, 38), (41, 39), (41, 40), (41, 41),
  (42, 23), (42, 24), (42, 25), (42, 26), (42, 27), (42, 28),
    (42, 37), (42, 38), (42, 39), (42, 40), (42, 41),

  # Action
  (43, 42), (43, 43),
  (44, 42), (44, 43),
  
  # Deli
  (45, 44), (45, 45), (45, 46),
  (46, 44), (46, 45), (46, 46),
  (47, 44), (47, 45), (47, 46),

  # Grill
  (48, 23), (48, 24), (48, 25), (48, 26), (48, 27), (48, 28),
  (49, 23), (49, 24), (49, 25), (49, 26), (49, 27), (49, 28),
  (50, 23), (50, 24), (50, 25), (50, 26), (50, 27), (50, 28),
    (50, 29), (50, 30),
  (51, 23), (51, 24), (51, 25), (51, 26), (51, 27), (51, 28),
    (51, 29), (51, 30),
  (52, 23), (52, 24), (52, 25), (52, 26), (52, 27), (52, 28),
  (53, 23), (53, 24), (53, 25), (53, 26), (53, 27), (53, 28),
  (54, 12), (54, 13), (54, 14), (54, 15), (54, 16),
    (54, 23), (54, 24), (54, 25), (54, 26), (54, 27), (54, 28),
    (54, 29), (54, 30),
  (55, 23), (55, 24), (55, 25), (55, 26), (55, 27), (55, 28),
  (56, 23), (56, 24), (56, 25), (56, 26), (56, 27), (56, 28),
    (56, 37), (56, 38), (56, 39), (56, 40), (56, 41)
 
]

worker_capabilities = [WorkerCapability(int(d[0]), int(d[1])) for d in worker_capability_data]

worker_stations_map = {}
for wc in worker_capabilities:
  w = wc.worker_id
  worker_stations_map.setdefault(w, [])
  worker_stations_map[w].append(wc.station_id)

station_workers_map = {}
for wc in worker_capabilities:
  s = wc.station_id
  station_workers_map.setdefault(s, [])
  station_workers_map[s].append(wc.worker_id)

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
def get_dow_station_display_text(dow_stations):
  stations_per_week = []
  minutes = 0
  for dow in range(len(days_of_week)):
    stations_per_day = []

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
      stations_per_week.append("-")
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
    t = get_dow_station_display_text(dow_stations)
    print "%-20s %-s" % (n, t)

# Print the weeks' assignments by station
def print_workers_by_station(sln):
  for s in stations:

    # Extract the workers for this station,
    # put day of week first, then sort them.
    dow_workers = [(x[1], x[2]) for x in sln if x[0] == s.id]
    dow_workers.sort(key=lambda tup: tup[0])

    n = s.name
    t = get_worker_display_text(dow_workers)
    print "%-20s %-s" % (n, t)

def schedule_cost(s):
  pass

# Su has index 0; Sa has index 6
days_of_week = ['Su','M','Tu','W','Th','F','Sa']

def unpack_days(days):
  if days == "Su-Sa":
    return [0,1,2,3,4,5,6]
  elif days == "M,Tu,Th,F":
    return [1,2,4,5]
  elif days == "Su,Sa":
    return [0,6]
  elif days == "Su-Th":
    return [0,1,2,3,4]
  elif days == "M-F":
    return [1,2,3,4,5]
  elif days == "Su-Tu,Th-Sa":
    return [0,1,2,4,5,6]
  elif days == "Su,M,W-F":
    return [0,1,3,4,5]
  elif days == "M-Th,Sa":
    return [0,1,2,3,4,6]
  else:
    return []


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

# Return wid of candidate. Assumes station is open.
def choose_candidate_ranked(sln, slot, sid, dow, candidates_by_station):
  worker_minutes = get_worker_minutes_in_schedule(sln)
  candidates = [wid for wid in candidates_by_station[sid]
                if valid_candidate_no_overtime(sln, sid, dow, wid, worker_minutes[wid])]
  return choose_randomly_from_list(candidates)

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
    worker_minutes[w.id] = (-1) * w.hours_per_week * 60

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
      print "%s, %s  %0.2f" % (w.last_name, w.first_name, worker_minutes[w.id]/60)

# print_solution_by_tuple(empty_solution)
# print(station_workers_map)
# initial_solution = make_initial_solution_randomly(station_workers_map, empty_solution)
# initial_solution = make_initial_solution_no_conflicts(station_workers_map, empty_solution)
# initial_solution = make_initial_solution_no_conflicts_or_overtime(station_workers_map, empty_solution)
initial_solution = make_initial_solution_ranked(station_workers_map, empty_solution)

print_stations_by_worker(initial_solution)
print
print_workers_by_station(initial_solution)
print
print "cost", schedule_cost(initial_solution)

print
print_overtime_workers(initial_solution)

