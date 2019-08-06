import random
import math
# import optimization
import sys
import os

import time
import station
import worker
import worker_capability

# Worker menu
#    edit days off
#    edit capabilities
#    edit personal info

# Edit menu
#    manually add or remove assignment

# Add concept of week 1 vs. week 2


class Assignment(object):
  def __init__(self, sid, dow, wid):
    self.sid = sid
    self.dow = dow
    self.wid = wid

  def to_tuple(self):
    return (self.sid, self.dow, self.wid)


class WeeklySchedule(object):
  def __init__(self, start_date, end_date, filename_zero, filename):
    self.start_date    = start_date
    self.end_date      = end_date
    self.filename_zero = filename_zero
    self.filename      = filename

    self._assignments  = []
    
class AppConfig(object):
  def __init__(self):
    self.current_week = WeeklySchedule("2017-03-05", "2017-03-11", "assignments-zero.txt", "assignments.txt")


def print_solution_by_tuple(sln):
  for x  in sln:
    sid = x[0]
    dow = x[1]
    wid = x[2]

    s = station.find_station_by_id(sid)
    d = time.days_of_week[dow]
    w = worker.get_assignment_display_text(wid)
 
    print "%-10s %-2s %-10s" % (s.name, d, w)

# Print a compact human-readable week's schedule.
def print_stations_by_worker(sln):
  for w in worker.workers:

    # Extract the assignments for this worker,
    # put day of week first, then sort them.
    dow_stations = [(x[1], x[0]) for x in sln if x[2] == w.id]
    dow_stations.sort(key=lambda tup: tup[0])
    # print dow_stations

    n = w.last_name + ", " + w.first_name
    t = station.get_dow_station_display_text(w, dow_stations)
    print "%-25s %-s" % (n, t)

# Print the weeks' assignments by station
def print_workers_by_station(sln):
  for s in station.stations:

    # Extract the workers for this station,
    # put day of week first, then sort them.
    dow_workers = [(x[1], x[2]) for x in sln if x[0] == s.id]
    dow_workers.sort(key=lambda tup: tup[0])

    n = s.name
    t = worker.get_worker_display_text(dow_workers)
    print "%-20s | %-s |" % (n, t)



# A solution is a list of slots, where a slot is a triplet
# (station id, day of week, worker id).
#
# A worker id of 0 indicates an unassigned slot (there is no worker with id 0);
# -1 indicates an invalid slot (the station isn't open that day).
def make_empty_solution():
  sln = []
  for dow in range(len(time.days_of_week)):
    for s in station.stations:
      sln.append((s.id, dow, station.get_empty_assignment(s, dow)))
  return sln

empty_solution = make_empty_solution()

def find_slot_by_station_id_and_dow(sln, sid, dow):
  for slot in sln:
    if slot[0] == sid and slot[1] == dow:
      return slot
  print "Didn't find slot for station %d and dow %d" % (sid, dow)
  sys.exit 

def find_slots_by_worker_id_and_dow(sln, wid, dow):
  return [slot for slot in sln if slot[2] == wid and slot[1] == dow]

def valid_candidate(sln, sid, dow, wid):
  # If the worker has a benefit day or comp time, consider invalid.
  w = worker.find_worker_by_id(wid)
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
  bad_slots = [slot for slot in slots if not station.are_compatible_stations(sid, slot[0])]
#  print "bad_slots", bad_slots
  return len(bad_slots) == 0

def valid_candidate_no_overtime(sln, sid, dow, wid, worker_min):
  if valid_candidate(sln, sid, dow, wid):
    s = station.find_station_by_id(sid)
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
  dow_stations.sort(key = lambda tup: tup[0] * 10000 + time.time_to_min(station.find_station_by_id(tup[1]).start_time))

  # Pair up successive assignments.
  pairs = zip(dow_stations, tail(dow_stations))

  # Discard pairs within same day.
  pairs2 = [p for p in pairs if p[0][0] != p[1][0]]

  # Extract stations from pairs.
  pairs3 = [(p[0][1], p[1][1]) for p in pairs2]

  # Compute the gaps between station pairs.
  gaps = map(station.get_station_gap_minutes, pairs3)

  return gaps

def get_worker_assignment_stats(sln, dow, wid):
  w = worker.find_worker_by_id(wid)
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
  s = station.find_station_by_id(sid)

  print
  print "station", sid, s.name
  print "day of week", dow, time.days_of_week[dow]
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
        w = worker.find_worker_by_id(wid)
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
  for s in station.stations:
    for dow in range(len(time.days_of_week)):
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
  for w in worker.workers:
    slots = [slot for slot in sln if slot[2] == w.id]
    ss = worker_capability.worker_stations_map[w.id]
    if len(ss) == 1:
      s = station.find_station_by_id(ss[0])
      only_candidate = {}
      only_candidate[s.id] = [w.id]
      for dow in range(len(time.days_of_week)):
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
  for w in worker.workers:
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
  for w in worker.workers:
    worker_minutes[w.id] = (-1) * w.hours_per_week * 60 + len(w.benefit_days) * 8 * 60

  for slot in sln:
    sid = slot[0]
    wid = slot[2]
    if wid > 0:
      s = station.find_station_by_id(sid)
      worker_minutes[wid] += s.get_station_duration()

  return worker_minutes
  
def print_overtime_workers(sln):
  worker_minutes = get_worker_minutes_in_schedule(sln)
  for w in worker.workers:
    if worker_minutes[w.id] > 0:
      name = w.last_name + ", " + w.first_name
      print "%-24s %0.2f" % (name, worker_minutes[w.id]/60)

def print_undertime_workers(sln):
  worker_minutes = get_worker_minutes_in_schedule(sln)
  for w in worker.workers:
    if worker_minutes[w.id] < 0:
      name = w.last_name + ", " + w.first_name
      print "%-24s %0.2f" % (name, worker_minutes[w.id]/60)


def format_slot_comment_for_file(slot):
  s = station.find_station_by_id(int(slot[0]))
  station_name = s.name

  day_name = time.days_of_week[int(slot[1])]

  wid = int(slot[2])
  worker_name = "OPEN"
  if wid > 0:
    w = worker.find_worker_by_id(int(slot[2]))
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
    s = station.find_station_by_id(sid)
    station_name = s.name
    ss.append("%1d=%s" % (sid, s.name))
  stations_comment = ", ".join(ss)
  w = worker.find_worker_by_id(wid)
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
  sorted_assignments.sort(key=lambda tup: worker.find_worker_by_id(tup[2]).sort_order * 100 + tup[1])
    
  for slot in sorted_assignments:
    t = format_slot_comment_for_file(slot)
    text_file.write(t)
    t = format_slot_for_file(slot)
    text_file.write(t)
  text_file.close()


def save_solution_sorted(sln, f):
  worker_assignment_map = {}
  for w in worker.workers:
    sorted_assignments = [(x[0], x[1], x[2]) for x in sln if x[2] == w.id]
    sorted_assignments.sort(key=lambda tup: worker.find_worker_by_id(tup[2]).sort_order * 100 + tup[1])
    worker_assignment_map[w.id] = sorted_assignments
    
  sorted_workers = [(w.id, w.sort_order) for w in worker.workers]
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
# print(worker_capability.station_workers_map)
# initial_solution = make_initial_solution_randomly(worker_capability.station_workers_map, empty_solution)
# initial_solution = make_initial_solution_no_conflicts(worker_capability.station_workers_map, empty_solution)
# initial_solution = make_initial_solution_no_conflicts_or_overtime(worker_capability.station_workers_map, empty_solution)
# initial_solution = make_initial_solution_ranked(worker_capability.station_workers_map, empty_solution)

# solution_1 = assign_workers_to_only_capability(worker_capability.station_workers_map, empty_solution, choose_candidate_ranked)
# print
# print_stations_by_worker(solution_1)
# print
# print_workers_by_station(solution_1)
# 
# initial_solution = make_initial_solution_ranked(worker_capability.station_workers_map, solution_1)
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
# print "total contracted hours", worker.total_contracted_hours()
# print
# print "total station hours", station.total_station_hours()

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
  prompt = "File (%s): " % f
  choice = raw_input(prompt)
  if not choice:
    return f
  else:
    return choice

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
  solution = assign_workers_to_only_capability(worker_capability.station_workers_map, solution, choose_candidate_ranked)
  print "Open stations have been assigned to workers with a single qualification."
  edit_menu()

def edit_assign_stations_by_rank():
  global solution
  solution = make_initial_solution_ranked(worker_capability.station_workers_map, solution)
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

def worker_get_info():
  pass

def worker_get_assignments():
  pass

def worker_add_assignment():
  pass

def worker_remove_assignment():
  pass

def main_menu():
  print "Enter the number of a command or submenu:"
  print "1. File menu"
  print "2. Edit menu"
  print "3. Options menu"
  print "4. Reports menu"
  print "5. Worker menu"
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


def worker_menu():
  print "Worker Menu"
  print
  print "51. Get personal information"
  print "52. Get assignments"
  print "53. Add assignment"
  print "54. Remove assignment"
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

  , '5': worker_menu
  , '51': worker_get_info
  , '52': worker_get_assignments
  , '53': worker_add_assignment
  , '54': worker_remove_assignment
}

if __name__ == "__main__":
  main_menu()

