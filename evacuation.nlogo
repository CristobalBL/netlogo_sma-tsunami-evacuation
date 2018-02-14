extensions [ gis csv ]
globals [
  roads
  centroids
  patches-color
  warning-turtle-color
  die-turtle-color
  safe-turtle-color
  mouse-up?
  scale-factor ;; scale factor between GIS coordinates and NetLogo coordinates; unit = meter
  avg_speed
  ;; Tsunami parameters
  curr_flooded-coord ;; current flooded limit coordinate
  tsunami_speed ;; Tsunami flooded speed (pixels/update)
  ;; evaluation parameters
  safe-agents
  die-agents
  agents-in-danger
  added_speed
  way-points
]

patches-own[
  flooded?
  safe-zone?
  road?
  way-point
]

turtles-own[
  die?
  safe?
  curr_speed
]

to setup
  ca
  reset-ticks
  setup-plots
  print "RUN! ..."

  ;; setup globals
  set safe-agents 0
  set agents-in-danger 0
  set die-agents 0
  set added_speed 0
  set way-points []

  setup-map

  setup-patches

  setup-turtles

  setup-tsunami

  print "OK!"
end

to go

  if ticks >= stop-time [  stop ]
  ;; move turtles
  update-agents

  ;; update tsunami
  update-tsunami-state

  tick-advance 1
  update-plots
end

to setup-map
  print "Setup map ... "
  ;import-drawing "data/portland/portland5.png"

  set roads gis:load-dataset (word data_dir data_filename)
  gis:set-world-envelope gis:envelope-of roads

  let x-ratio (item 1 gis:envelope-of roads - item 0 gis:envelope-of roads) / ( max-pxcor - min-pxcor )
  let y-ratio (item 3 gis:envelope-of roads - item 2 gis:envelope-of roads) / ( max-pycor - min-pycor )

  ;; the greater ratio defines the correct scale factor between GIS coords and NetLogo coords
  ifelse x-ratio > y-ratio [set scale-factor x-ratio][set scale-factor y-ratio]

end

to setup-patches
  print "Setup patches ... "

  ;; setup roads
  set patches-color sky
  let patches_path (word data_dir "patches.png")


  ifelse file-exists? patches_path
  [
    import-pcolors patches_path

    ask patches [
      set road? false
      set flooded? false
      set safe-zone? false

      ;; set waypoint
      set way-point []
      set way-point lput -1 way-point
      set way-point lput -1 way-point
    ]

    ask patches with [ pcolor = patches-color ] [ set road? true ]

  ][

    ask patches [
      set road? false
      set flooded? false
      set safe-zone? false
      ;; set waypoint
      set way-point []
      set way-point lput -1 way-point
      set way-point lput -1 way-point
      if gis:intersects? roads self [ set pcolor patches-color set road? true]
    ]

    export-view patches_path
  ]

  ; prefix streetname ftype etr_id routename route_from route_to owner
  print gis:property-names roads

  gis:set-drawing-color white
  gis:draw roads 0.5

  let i 1
  ask patches with [ road? ] [ set i i + 1]
  print word "road patches " i

  ;; setup safe zones
  setup-safe-zones

end

to setup-safe-zones


  let safe-zones_list csv:from-file (word data_dir evacuation-zones_file)

  foreach safe-zones_list [ r ->

    let x_ezone item 0 r
    let y_ezone item 1 r

    let width item 2 r
    let height item 3 r

    ;; Put center of current safe-zone into way-points
    let center_x round (x_ezone +  width / 2)
    let center_y round (y_ezone - height / 2)
    print (word center_x center_y)
    let center []
    set center lput center_x center
    set center lput center_y center

    set way-points lput center way-points

    ;; Add patches into safe-zone rect with parameters of safe-zone
    ask patches with [ (pxcor  >= x_ezone and pxcor <= x_ezone + width ) and ( pycor <= y_ezone and pycor >= y_ezone - height  ) ] [

      set safe-zone? true
      set road? false
      ifelse pxcor = item 0 center and pycor = item 1 center [ set pcolor red ] [ set pcolor 136 ]

      set way-point replace-item 0 way-point item 0 center
      set way-point replace-item 1 way-point item 1 center
    ]

    ask patches with [ safe-zone? and any? neighbors4 with [ road? ] ] [
      print (word "Way point limit -> " pxcor "," pycor)
      let pt []
      set pt lput pxcor pt
      set pt lput pycor pt
      set way-points lput pt way-points
      set pcolor red
    ]

  ]

  ask patches with [ road? ] [

    let agent_set []
    let x -1
    let y -1
    let min_distance 100000
    foreach way-points [ center ->
      let center_x item 0 center
      let center_y item 1 center
      ask patch center_x center_y [
        let curr_distance distance myself
        if curr_distance < min_distance [
          set x pxcor
          set y pycor
          set min_distance curr_distance
        ]
      ]

    ]

    set way-point replace-item 0 way-point x
    set way-point replace-item 1 way-point y
  ]

  print (word "Way-points: " way-points)

end

to setup-turtles
  print "Setup turtles ... "

  set warning-turtle-color 46
  set safe-turtle-color green
  set die-turtle-color red
  set avg_speed (avg_agent-speed * scale-factor) * 60 / 3.6
  let n_turtles agent_number

  print (word "Factor de escala: " scale-factor)
  print (word "Velocidad promedio: " avg_speed)

  let search-radius 100 ;; radius to find road

  create-turtles n_turtles


  ;; Max patch with road?
  let max_y 0
  ask max-one-of patches with [ road? and pycor < lim_y_turtles ] [pycor]
  [ set max_y  pycor]
  let min_y 0
  ask min-one-of patches with [ road? and pycor > lim_y_turtles - lim_height_turtles] [pycor]
  [ set min_y pycor ]
  let max_x 0
  ask max-one-of patches with [ road? and pxcor < lim_x_turtles + lim_width_turtles] [pxcor]
  [ set max_x pxcor ]
  let min_x 0
  ask min-one-of patches with [ road? and pxcor > lim_x_turtles] [pxcor]
  [ set min_x pxcor ]

  print (word "Max values " max_x ", " min_x "," max_y ", " min_y)

  ask turtles [

    ;; Set initial parameters
    ;; to leave the random positions near the roads
    setxy (min_x + (random (max_x - min_x )) ) (min_y + (random (max_y - min_y ) ) )

    set color warning-turtle-color
    set die? false
    set safe? false
    set agents-in-danger agents-in-danger + 1

    ;; Move turtles to intial position
    let target-patch one-of (patches in-radius search-radius with [
      road?
      and count turtles-here < agents-per-patch
      and pycor < lim_y_turtles and pycor > lim_y_turtles - lim_height_turtles
      and pxcor > lim_x_turtles and pxcor < lim_x_turtles + lim_width_turtles
    ])

    if target-patch != nobody  [
      move-to target-patch
    ]
  ]

end


to setup-tsunami
  set curr_flooded-coord max-pycor;; current flooded limit coordinate
  set tsunami_speed (-(avg_tsunami-speed * scale-factor) * 60 / 3.6) ;; Tsunami flooded speed (pixels/update)
end

to update-tsunami-state
  if ticks > tsunami_start-time and curr_flooded-coord > flooded-coord-th [
    ;; flood
    ask patches with [ pycor > curr_flooded-coord and safe-zone? = false and flooded? = false] [ set pcolor 98 set flooded? true]

    ;; update
    set curr_flooded-coord curr_flooded-coord + tsunami_speed

  ]
end

to update-agents
  ;; Si aún no esta evacuado, debe moverse
  ;; Si ya fue evacuado, moverse dentro de la zona de evacuación
  ;; Si murio, no se mueve
  set added_speed 0

  ;; Update not die agents
  ask turtles with [ die? = false ] [

    ;; Manage agent state
    let hasToDie false
    let isSafe safe?
    ask patch-here [
      if flooded?[
        set die-agents die-agents + 1
        set agents-in-danger agents-in-danger - 1
        set hasToDie true
      ]

      if hasToDie = false [
        ;; If change from safe-zone to road
        ifelse isSafe = true and road? [
          set agents-in-danger agents-in-danger + 1
          set isSafe false
        ][
          ;; If change from road to safe-zone
          if isSafe = false and safe-zone? [
            set agents-in-danger agents-in-danger - 1
            set isSafe true
          ]
        ]
      ]

    ]


    ifelse hasToDie [
      set color die-turtle-color
      set die? true
      set safe? false
    ][
      set safe? isSafe
      if safe? [set color safe-turtle-color ]
    ]

    let speed avg_speed

    ;; Move agent behaviour
    if die? = false [

      let valid-move-patches neighbors with [ can-move-to self ]

      if any? valid-move-patches [

        ifelse safe? = false [
          move-to-securezone speed valid-move-patches
        ]
        [
          ;;print "move in secure zone"
          move-into-securezone speed valid-move-patches
        ]
      ]
    ]
  ]

end

to-report get-path-score [ own-distance time-facctor can-move-to-ahead ahead-x ahead-y]
  let congestion get-patch-congestion
  let dist-diff diff-in-distance-to-waypoint own-distance

  let factor1  ((1 - congestion) * time-facctor)
  let factor2  dist-diff
  let factor3  0
  if can-move-to-ahead and pxcor = ahead-x and pycor = ahead-y [ set factor3 random-float 0.5 ]
  let output (factor1 + factor2 + factor3)
  ;print (word "Patch " pxcor ", " pycor "->" factor1 " - " factor2)

  report output

end

;; Get congestion value for given patch
to-report get-patch-congestion
  report count_turtles_in_neighbors / (8 * agents-per-patch)
end

;; Get occupied neighbors patches for current patch
to-report count_turtles_in_neighbors

  let sum_turtles_in_neighbors 0
  ask neighbors [ set sum_turtles_in_neighbors sum_turtles_in_neighbors + count turtles-here ]

  report sum_turtles_in_neighbors
end

;; Given p, return true if current turtle can move to it, false elsewhere
to-report can-move-to [ p ]

  let output false

  ask p [ if (road? or safe-zone?) and (flooded? = false and count turtles-here < agents-per-patch) [ set output true] ]

  report output
end

to-report diff-in-distance-to-waypoint [ own-distance ]
  let diff  own-distance - distance patch item 0 way-point item 1 way-point
  ;print (word "patch at : " pxcor ", " pycor " -> "diff)
  report diff
end
;; sp: speed
to move-to-securezone [sp valid-patches]
  ;; Strategy nr 1
  ;; Busca primero un lugar seguro

  ;ask valid-patches [ print ( word "Pos where i can move: " pxcor ", " pycor) ]
  let temp_patch nobody

  ifelse ( any? valid-patches with [ safe-zone? ] )[
    set temp_patch one-of neighbors with [ safe-zone? ]
  ][

    ; Estrategia 0
    ;set temp_patch patch-ahead 1
    ;if can-move-to temp_patch = false [
    ;  set temp_patch one-of valid-patches with [ road? ]
    ;]

    ; Estrategia 1
    ;set temp_patch patch-ahead 1
    ;if can-move-to temp_patch = false [
    ;  let current_distance_to_way_point distance patch item 0 way-point item 1 way-point
    ;  set temp_patch max-one-of valid-patches [ diff-in-distance-to-waypoint current_distance_to_way_point ]
      ;print get-patch-congestion
    ;]

    ;print (word current_distance_to_way_point)
    ;set temp_patch min-one-of valid-patches [ distance patch item 0 way-point item 1 way-point ]

    ; Estrategia 2
    ;set temp_patch patch-ahead 1
    ;if can-move-to temp_patch = false [
    ;  set temp_patch min-one-of valid-patches [ get-patch-congestion ]
      ;print get-patch-congestion
    ;]

    ; Estrategia 3
    ;; Me sigo moviendo en la dirección que estaba
    ;; si no puedo moverse en esa dirección, busco el patch con mínima congestion

    ;ifelse (ticks / stop-time) < st3_time_threshold [
    ;  set temp_patch patch-ahead 1
    ;if can-move-to temp_patch = false [
    ;  set temp_patch min-one-of valid-patches [ get-patch-congestion ]
    ;]
      ;print "Congestion strategy"
    ;] [
    ;    let current_distance_to_way_point distance patch item 0 way-point item 1 way-point
    ;    set temp_patch max-one-of valid-patches [ diff-in-distance-to-waypoint current_distance_to_way_point ]
        ;print get-patch-congestion
        ;print "Dist to waypoint strategy"
    ;]


    ;Estrategia 4
    ;; Estrategia 4: puntaje de patch en función de congestion de frente, cercania a waypoint, implicancia de acercarse al mar, me puedo seguir moviendo en esa direccion
    ;; Suma de todas las demás
    let can-move-to-ahead can-move-to patch-ahead 1
    let x-ahead 0
    let y-ahead 0
    if can-move-to-ahead [
      ask patch-ahead 1 [ set x-ahead pxcor set y-ahead pycor  ]
    ]

    let current_distance_to_way_point distance patch item 0 way-point item 1 way-point
    set temp_patch max-one-of valid-patches [ get-path-score current_distance_to_way_point ((stop-time - ticks) / stop-time) can-move-to-ahead x-ahead y-ahead]

    ;print temp_patch
    ;print way-point
    ;print temp_patch
  ]

  ;; move turtle
  move-to-patch sp temp_patch

end

;; sp: speed
to move-into-securezone [sp valid-patches]
  ;; Move Safe agents
  ;;Se mueve solo en la zona segura
  let x_way-point -1
  let y_way-point -1

  ask one-of valid-patches with [ safe-zone? ][
     set x_way-point item 0 way-point
     set y_way-point item 1 way-point
  ]

  if x_way-point != -1 and y_way-point != -1 [
    move-to-patch sp patch x_way-point y_way-point
  ]

end

;; Move method: turn to target_patch and forward with sp +- random value
to move-to-patch [ sp target_patch ]
  if target_patch != nobody [
    face target_patch
    let speed sp + (-1 + random-float( 2 )) * sp * 0.2
    forward speed
    set curr_speed speed
    set added_speed added_speed + speed
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
261
10
1352
1102
-1
-1
3.0
1
10
1
1
1
0
1
1
1
-180
180
-180
180
0
0
1
ticks
30.0

BUTTON
58
62
131
95
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

INPUTBOX
1561
66
1664
126
agent_number
20000.0
1
0
Number

BUTTON
143
62
206
95
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
95
177
181
222
Evacuados
agent_number - (agents-in-danger + die-agents)
17
1
11

MONITOR
96
229
181
274
Muertos
die-agents
17
1
11

MONITOR
95
283
182
328
En peligro
agents-in-danger
17
1
11

PLOT
-1
352
257
538
Evacuados vs Muertos
ticks
agents
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"evacuados" 1.0 0 -13840069 true "" "plot count turtles with [ safe? = true ]"
"muertos" 1.0 0 -16580092 true "" "plot count turtles with [ die? = true ]"

INPUTBOX
1404
67
1522
127
avg_agent-speed
50.0
1
0
Number

INPUTBOX
1405
136
1523
196
avg_tsunami-speed
100.0
1
0
Number

INPUTBOX
1410
236
1524
296
agents-per-patch
25.0
1
0
Number

INPUTBOX
1412
333
1527
393
flooded-coord-th
55.0
1
0
Number

INPUTBOX
1564
333
1676
393
tsunami_start-time
60.0
1
0
Number

TEXTBOX
1404
29
1554
47
TURTLES
12
0.0
1

TEXTBOX
1409
209
1559
227
PATCHES
12
0.0
1

TEXTBOX
1413
305
1563
323
TSUNAMI
12
0.0
1

INPUTBOX
98
105
179
165
stop-time
2000.0
1
0
Number

INPUTBOX
1408
597
1601
657
evacuation-zones_file
evacuation_zones_3.csv
1
0
String

TEXTBOX
1417
438
1567
456
CITY
12
0.0
1

INPUTBOX
1407
460
1599
520
data_dir
data/valpo/
1
0
String

INPUTBOX
1407
530
1600
590
data_filename
valpo.shp
1
0
String

INPUTBOX
1628
459
1714
519
lim_x_turtles
-156.0
1
0
Number

INPUTBOX
1725
459
1816
519
lim_y_turtles
140.0
1
0
Number

INPUTBOX
1663
531
1773
591
lim_width_turtles
280.0
1
0
Number

INPUTBOX
1662
600
1775
660
lim_height_turtles
115.0
1
0
Number

TEXTBOX
1626
425
1776
455
Where can i put the turtles?
12
0.0
1

PLOT
-30
546
249
737
Global Speed
ticks
global speed
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot added_speed"

INPUTBOX
1566
143
1676
203
st3_time_threshold
0.2
1
0
Number

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.0.2
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
