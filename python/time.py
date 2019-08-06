def overlapping_times(s1, e1, s2, e2):
  # Sort the intervals so s1,e1 starts earlier in the day than s2,e2.
  if s1 > s2:
    # This statement swaps all the variables.
    s1, e1, s2, e2 = s2, e2, s1, e1
  # Deal with ending time past midnight. No starting time is past midnight.
  if e1 < s1:
    e1 += 2400
  return s2 < e1

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


