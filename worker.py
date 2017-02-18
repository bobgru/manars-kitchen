import time

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
    self.benefit_days   = time.unpack_days(benefit_days)
    self.comp_days      = time.unpack_days(comp_days)

worker_data = [
( 1,"Dickinson", "Theron",             "1st Cook",            1, 40, False,  7, "", ""),
(54,"Joseph", "Nicole",                "1st Cook",            2, 40, False,  4, "", ""),
( 3,"Sales", "Geraldo",                "1st Cook",            3, 40, False,  9, "", ""),
( 4,"Carballo", "Fabio",               "2nd Cook",            4, 40, False,  1, "", ""),
(17,"Carreiro", "Marcos",              "2nd Cook",            5, 40, False,  6, "", ""),
( 5,"Chludzinska", "Marianna",         "2nd Cook",            6, 40, True,   8, "", ""),
( 6,"Lagrant", "Leroy",                "2nd Cook",            7, 40, True,   0, "", ""),
( 7,"Law", "Philip",                   "2nd Cook",            8, 40, True,   0, "", ""),
( 8,"Lefteri", "Fotaq",                "2nd Cook",            9, 40, False,  3, "", ""),
( 9,"Lejentus", "Rene",                "2nd Cook",           10, 20, False,  4, "", ""),

(10,"Marku", "Zef",                    "2nd Cook",           11, 20, True,   5, "", ""),
(65,"Mayorga", "Tezla",                "2nd Cook",           12, 40, False,  0, "", ""),
(11,"Moreno", "Osvaldo",               "2nd Cook",           13,  0, True,   0, "", ""),
(12,"Ortiz", "Angela",                 "2nd Cook",           14, 40, False,  6, "", ""),
(13,"Sokolowska", "Czeslawa",          "2nd Cook",           15, 40, True,   1, "", ""),
(14,"Vaz", "David",                    "2nd Cook",           16, 20, True,  14, "", ""),
(15,"Velazques", "Hoover",             "2nd Cook",           17, 40, True,  14, "", ""),
(16,"Williams", "Veniesa",             "2nd Cook",           18, 16, True,   2, "", ""),
# missing person here
(21,"Caddeus", "Winfred",              "1st Cook",           20, 40, True,  12, "", ""),

(22,"Elorch", "Omar",                  "1st Cook",           21, 40, False, 15, "", ""),
(18,"Diaz", "Ruben",                   "2nd Cook",           22, 40, False, 11, "", ""),
(19,"El Mouttaki", "Mohamed",          "2nd Cook",           23, 40, True,  15, "", ""),
(24,"Almeda", "Jose Marcel",           "Shift Lead",         24, 40, False, 16, "", ""),
(25,"Buckley", "John",                 "Shift Lead",         25, 40, False, 16, "", ""),
(23,"Portillo", "Jorge",               "1st Cook",           26, 40, True,  10, "", ""),
(59,"Vasconuelos", "Antonio",          "Shift Lead",         27, 32, True,  13, "", ""),
(27,"Millard", "Brian",                "Sous Chef",          28, 40, True,  47, "", ""),
(61,"Rocha", "Fabio",                  "Sous Chef",          29, 40, False, 48, "", ""),
(28,"Barros", "Deila",                 "Prod-Aide",          30, 40, True,  19, "", ""),

(62,"Briskaj", "Alketa",               "Prod-Aide",          31, 40, False, 22, "", ""),
(29,"Chodkowska", "Marzena",           "Prod-Aide",          32, 40, True,  20, "", ""),
(30,"Kozlowski", "Jadwiga",            "Prod-Aide",          33, 40, False, 20, "", ""),
(63,"Mehari", "Meaza",                 "Prod-Aide",          34, 40, False, 22, "", ""),
(31,"Samuel", "Willie James",          "Prod-Aide",          35, 40, True,  21, "", ""),
(32,"McCormack", "David",              "Material",           36, 40, False, 24, "", ""),
(60,"Selman", "Deric",                 "Prod-Aide",          37, 40, True,  46, "", ""),
(64,"Velasquez", "Jesus",              "Prod-Aide",          38, 40, False, 46, "", ""),
(33,"Fofana", "Abu",                   "Receiver",           39, 40, True,  26, "", ""),
(34,"Morano", "Juan",                  "Receiver",           40, 40, False, 25, "", ""),

(35,"Coren", "Gregorey",               "Sr. Material",       41, 40, False, 23, "", ""),
(36,"Cuthbert Jr", "Ezekiel",          "Supply Clerk",       42, 40, False, 27, "", ""),
(58,"Alby", "Taoufik",                 "2nd Cook",           43, 40, False, 39, "", ""),
(40,"Echavarria", "Fernando",          "2nd Cook",           44, 40, True,  39, "", ""),
(41,"Frontin", "Sheldon",              "2nd Cook",           45, 40, True,  38, "", ""),
(42,"Soriano", "Rene",                 "2nd Cook",           46, 40, False, 41, "", ""),
(43,"Cortell", "Glenn",                "2nd Cook",           47, 40, True,  37, "", ""),
(44,"Joseph", "Paul",                  "2nd Cook",           48, 40, False, 36, "", ""),
(45,"Pyskaty", "Maria",                "Prod-Aide",          49, 40, False, 43, "", ""),
(46,"Terron", "Maria",                 "Prod-Aide",          50, 40, False, 42, "", ""),

(47,"Campbell", "Trevon",              "Prod-Aide",          51, 40, True,  44, "", ""),
( 2,"Kanina", "Ewa",                   "1st Cook",           52, 40, False, 35, "", ""),
(57,"Almeida", "Anthony",              "2nd Cook",           53, 40, False, 33, "", ""),
(49,"Danial", "Clebert",               "2nd Cook",           54, 40, False, 32, "", ""),
(50,"Guevara", "Henry",                "2nd Cook",           55, 40, True,  30, "", ""),
(51,"Hines", "Michael",                "2nd Cook",           56, 40, True,  29, "", ""),
(52,"Murcia", "Alex",                  "2nd Cook",           57, 40, False, 28, "", ""),
(53,"Way", "Shon",                     "2nd Cook",           58, 40, False, 29, "", ""),
(55,"Bailey", "James",                 "2nd Cook",           59,  0, True,   0, "", ""),
(56,"Miller", "Edward",                "2nd Cook",           60,  0, True,   0, "", "")

]

workers = [Worker(int(d[0]), d[1], d[2], d[2], int(d[4]), int(d[5]), d[6], int(d[7]), d[8], d[9]) for d in worker_data]
worker_map = {}
for w in workers:
  worker_map[w.id] = w

def total_contracted_hours():
  hours = map(lambda w: w.hours_per_week, workers)
  return sum(hours)

def find_worker_by_id(wid):
  return worker_map[wid]

def get_assignment_display_text(wid):
  if wid < 0:
    return 'N/A'
  elif wid == 0:
    return '-'
  else:
    return find_worker_by_id(wid).last_name

# Assumes dow_workers are sorted by day of week.
def get_worker_display_text(dow_workers):
  workers_per_week = []
  for dow in range(len(time.days_of_week)):
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


