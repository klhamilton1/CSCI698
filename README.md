# Two-Batch Brew Day Simulation

A SIMAN discrete-event simulation of a small brewery's two-batch brew day, built as a semester capstone project in simulation modeling.

Jeff, the brewer, brews two batches in one day using a single mash tun, a single boil tun and two fermenters, and he does all the work himself. The study answers two questions:

1. **When should Batch 2 start?** The start time TB2 is measured in minutes after Batch 1's fill begins and is set for each Batch 1 beer.
2. **Should mash 2 wait until Batch 1's boil tun has been tilted?** Or can it go ahead whenever it is ready?

## Key Findings

- **Don't wait for the tilt.** Holding mash-in until the tilt adds about 23 minutes to the day, and holding the Batch 2 fill adds about 74 minutes.
- **Start Batch 2 slightly earlier than today's 5:00.** Use the start times below, which depend on the Batch 1 beer:

  | Batch 1 beer | Start Batch 2 (h:mm after Batch 1 fill) |
  |---|---|
  | Hefeweizen | 4:43 |
  | Lawnmower | 4:45 |
  | Summer Snatch, Kolsch | 4:47 |
  | 1781 | 4:49 |
  | Bourbon Vanilla, Dubble Aught | 4:53 |

- **Expected effect:**
  - The day gets about 9 minutes shorter on average, from 11 h 18 min.
  - Tilt delays drop from about 26% of days to about 17%.
  - The mash tun is already clean when Batch 2 needs it on about 96% of days.

All results are in the final report (Assignment 5).

## Model Overview

- **Entities:**
  - Batch 1 and Batch 2: one entity each.
  - A controller entity: reads the replication number and sets the scenario.
- **Resources:**
  - Jeff, the only worker.
  - Mash tun and boil tun.
  - Hot-water line.
  - Two fermenters.
- **Jeff's task priorities:** tilt (1), then brewing (2), then cleaning (3).
- **Inputs:**
  - Fill volumes for each beer, from Jeff's fill depths at 1.585 in per 5 gal.
  - Fill rate of 2.5 gal/min.
  - Fitted distributions (Weibull, gamma, normal, uniform) for heat, transfer and cleaning times.
- **Run boundary:** a replication is one brew day, from the start of Batch 1's fill until Batch 2 enters its fermenter. It is a terminating simulation with no warm-up.
- **Policy variable `MashGate`:**
  - `0`: no hold.
  - `1`: hold mash-in until the tilt.
  - `2`: hold the fill until the tilt.

### Matrix runs

Instead of building one SIMAN job per scenario, `BrewDay.mod` reads `NREP` at the start of each replication. It uses that number to look up its scenario in arrays defined in the `.exp` file:

```
Scen = AINT((NREP - 1) / RepsPer) + 1
TB2 = ScTB2(Scen), Beer1Type = ScB1(Scen), Beer2Type = ScB2(Scen), MashGate = ScGate(Scen)
```

The two experiments use the same model:

- **Experiment A** (`BrewExpA.exp`) runs each Batch 1 beer at TB2 = 300 for 2,000 replications. The time the mash tun finishes cleaning does not depend on TB2, so the recommended start for each beer is the 95th percentile of that clean time.
- **Experiment B** (`BrewExpB.exp`) runs 4 policies on all 49 beer pairings, with 200 replications each (39,200 in total).

## How to Run

Requires the SIMAN Run Processor (tested with 16.20.00).

1. Copy `BrewDay.mod`, `BrewExpA.exp`, `BrewExpB.exp` and the scripts into one folder.
2. Build the model file with `model.exe BrewDay.mod`
4. Build experiment A file with `expmt.exe BrewExpA.mod`
5. Link files together with `linker.exe BrewDay.m BrewExpA.e BrewDay.p`
6. Execute the model with `siman.exe BrewDay.p > output_A.txt`
7. Repeat steps 4-6 with BrewExpB.exp.
8. The output appears as `output_A.txt` / `output_B.txt` (SIMAN output).

You can also build and run `cap.mod` with each `.exp` file by hand and save the screen output to a text file.

Seeds: streams 1–7, seeds 100–160, `Initialize = No`.

## Validation

The model was run at the beer pairings and Batch 2 start times of Jeff's 12 logged two-batch days:

| | Mean makespan |
|---|---|
| Model | 680 min |
| Jeff's logged days | 678 min |

On 10 of the 12 days, the observed makespan fell inside the model's 10th–90th percentile range.

## Author

Kate Hamilton. Capstone simulation project, 2026.
