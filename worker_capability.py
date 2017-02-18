import station
import worker

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
for w in worker.workers:
  worker_stations_map[w.id] = []
for wc in worker_capabilities:
  sid = wc.station_id
  wid = wc.worker_id
  worker_stations_map[wid].append(sid)

station_workers_map = {}
for s in station.stations:
  station_workers_map[s.id] = []
for wc in worker_capabilities:
  sid = wc.station_id
  wid = wc.worker_id
  station_workers_map[sid].append(wid)

