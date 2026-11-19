BEGIN;

          CREATE, 1, 0: 1440, 1;                      Batch 1 at start of day
          ASSIGN: Seq = 1:
                  BType = Beer1Type:   NEXT(Brew);       BType: 1 Small, 2 Medium, 3 Large
 
          CREATE, 1, TB2: 1440, 1;                    Batch 2 at chosen start
          ASSIGN: Seq = 2:
                  BType = Beer2Type:   NEXT(Brew);
 
Brew      ASSIGN: ArrT = TNOW;
; wait for a clean mash tun
          QUEUE,  MashTunQ;
          SEIZE,  1: MashTun, 1;
          ASSIGN: TMTWait = TNOW - ArrT:
                  MTIdle  = MX(0, ArrT - MTCleanT);

; MashGate = 2: Batch 2 does not start fill until Batch 1's tilt done
          ASSIGN: TStamp = TNOW;
          BRANCH, 1: IF, Seq == 2 .AND. MashGate == 2, GateFill, Yes:
                     ELSE, Fill, Yes;
GateFill  QUEUE, FillGateQ;
          SCAN: TiltDone(1) == 1;
Fill      ASSIGN: GateWait = TNOW - TStamp;
 
; 1-min setup buffer, then deterministic fill (FillRate = 2.5 gal/min)
          QUEUE,  JBufFillQ;
          SEIZE,  1: Jeff, 1;
          DELAY:  Buf;
          RELEASE: Jeff, 1;
          QUEUE,  HWFillQ;
          SEIZE,  1: HotWater, 1;
          DELAY:  FillVol(BType) / FillRate;          unattended fill
          RELEASE: HotWater, 1;
 
; stochastic mash-water heat time (unattended)
          DELAY:  5.5 + WEIB(15.6, 1.6, 1);

; MashGate = 1: Batch 2 does not start mash-in until Batch 1's tilt is done
          ASSIGN: TStamp = TNOW;
          BRANCH, 1: IF, Seq == 2 .AND. MashGate == 1, GateMI, Yes:
                     ELSE, MashIn, Yes;
GateMI    QUEUE,  MashInGateQ;
          SCAN:   TiltDone(1) == 1;
          ASSIGN: GateWait = TNOW - TStamp:   NEXT(MashIn);
 
; mash-in + 1-min buffer
          QUEUE,  JMashInQ;
          SEIZE,  1: Jeff, 1;
          ASSIGN: TMashIn = TNOW;
          DELAY:  MashInT + Buf;
          RELEASE: Jeff, 1;
 
; Batch 1 starts the fermenter-cleaning job at the start of its mash rest
          BRANCH, 1: If, Seq == 1, DupFC, Yes:
                     Else, MashRest, Yes;
DupFC     DUPLICATE: 1, FermClean;
 
; mash rest 48 min (mash-in + rest = 60), buffer, mash-out 10 min, buffer, recirculation 30 min
MashRest  DELAY:  MashT;
          QUEUE,  JBufMashQ;
          SEIZE,  1: Jeff, 1;
          DELAY:  Buf;
          RELEASE: Jeff, 1;
          DELAY:  MashOutT;
          QUEUE,  JBufMOQ;
          SEIZE,  1: Jeff, 1;
          DELAY:  Buf;
          RELEASE: Jeff, 1;
          DELAY:  RecircT;
 
; wait for a clean boil tun; recirculation continues while waiting
          ASSIGN: TStamp = TNOW;
          QUEUE,  BoilTunQ;
          SEIZE,  1: BoilTun, 1;
          ASSIGN: TBTWait = TNOW - TStamp;
 
; buffer + sparge/transfer to boil tun
          QUEUE,  JSpargeQ;
          SEIZE,  1: Jeff, 1;
          QUEUE,  HWSpargeQ;
          SEIZE,  1: HotWater, 1;
          ASSIGN: TrBoil = 25 + GAMM(13, 1.62, 2);
          DELAY:  Buf + TrBoil;
          RELEASE: Jeff, 1:
                   HotWater, 1;
          ASSIGN: TLeaveMT = TNOW;
 
; Batch 1 leaves a dirty mash tun -> mash-tun cleaning job
          BRANCH, 1: If, Seq == 1, DupMT, Yes:
                     Else, PreBoil, Yes;
DupMT     DUPLICATE: 1, MTClean;
 
; pre-boil heating by beer group
PreBoil   ASSIGN: PreBoilT = MN(75, MX(20,
                     PBMean(BType)
                   + PBRho * PBSD(BType) / TrSD * (TrBoil - TrMean)
                   + PBSD(BType) * PBk * NORM(0, 1, 3)));
          DELAY:  PreBoilT;
 
; 60-min boil 
          DELAY:  BoilT;
 
; wait for a clean fermenter; wort held in the boil tun
          ASSIGN: TStamp = TNOW;
          QUEUE,  FermQ;
          SCAN:   CleanFerm >= 1;
          ASSIGN: CleanFerm = CleanFerm - 1:
                  TFWait    = TNOW - TStamp;
 
; buffer (hose/valve setup, Jeff), then transfer through the chill plate
          QUEUE,  JBufFermQ;
          SEIZE,  1: Jeff, 1;
          DELAY:  Buf;
          RELEASE: Jeff, 1;
          QUEUE,  ChillQ;
          SEIZE,  1: ChillPlate, 1;
          BRANCH, 1: If, Seq == 1, TrF1, Yes:
                     Else, TrF2, Yes;
TrF1      ASSIGN: TrFerm = NORM(57.7, 5.83, 4):        NEXT(DoTrF);
TrF2      ASSIGN: TrFerm = 47.5 + GAMM(9.25, 2.0, 5):  NEXT(DoTrF);

DoTrF     ASSIGN: TiltT = UNIF(TiltGalLo, TiltGalHi, 7) * TrFerm / FermBatchVol;
          DELAY:  MX(0, TrFerm - WatchT - TiltT - KillT);      (a) pumped
          ASSIGN: TStamp = TNOW;
          QUEUE,  JTiltQ;
          SEIZE,  1: Jeff, 1;                                  (b) priority 1
          ASSIGN: TiltWait(Seq) = TNOW - TStamp;
          DELAY:  WatchT + TiltT + KillT;
          RELEASE: Jeff, 1;
          RELEASE: ChillPlate, 1;
          ASSIGN: TiltDone(Seq) = 1;
 
; Batch 1 leaves a dirty boil tun -> boil-tun cleaning job
          BRANCH, 1: If, Seq == 1, DupBT, Yes:
                     Else, Depart, Yes;
DupBT     DUPLICATE: 1, BTClean;
 
Depart    TALLY:  BatchCycle, INT(ArrT), 1;
          BRANCH, 1: If, Seq == 2, B2Stats, Yes:
                     Else, Out, Yes;
B2Stats   TALLY:  Makespan,    TNOW, 1;
          TALLY:  B2MTWait,    TMTWait, 1;
          TALLY:  Conflict,    TMTWait > 0.01, 1;
          TALLY:  MTIdleT,     MTIdle, 1;
          TALLY:  B2BTWait,    TBTWait, 1;
          TALLY:  B2FWait,     TFWait, 1;
          TALLY:  B2Gap,       TMashIn - LeaveMT1, 1;
          TALLY:  B1TiltWait,  TiltWait(1), 1;
          TALLY:  TiltClash,   TiltWait(1) > 0.01, 1;
          TALLY:  B2TiltWait,  TiltWait(2), 1;
          TALLY:  B2MIWait,    MIWait, 1;
          TALLY:  B2GateWait,  GateWait, 1;
Out       COUNT:  BatchesDone, 1;                     limit 2 ends the run
          DISPOSE;

; Fermenter cleaning job, both fermenters
 
FermClean QUEUE,  FCFill1Q;                           1 F1 hot water + OxiClean
          SEIZE,  3: HotWater, 1;
          DELAY:  FermVol / FillRate;
          RELEASE: HotWater, 1;
          QUEUE,  FCFill2Q;                           2 F2 hot water + OxiClean
          SEIZE,  3: HotWater, 1;
          DELAY:  FermVol / FillRate;
          RELEASE: HotWater, 1;
          ASSIGN: F2Ready = TNOW + FSit + FermVol / DrainRate;
          QUEUE,  FCR1ScanQ;                          3 spray F1, UNIF(4,5)
          SCAN:   NR(Jeff) == 0 .AND. NR(HotWater) == 0;
          QUEUE,  FCR1JQ;
          SEIZE,  3: Jeff, 1;
          QUEUE,  FCR1HQ;
          SEIZE,  3: HotWater, 1;
          DELAY:  UNIF(4, 5, 6);
          RELEASE: Jeff, 1: HotWater, 1;
          DELAY:  MX(0, F2Ready - TNOW);              4 wait for F2 to drain
          QUEUE,  FCR2ScanQ;                          5 spray F2, UNIF(4,5)
          SCAN:   NR(Jeff) == 0 .AND. NR(HotWater) == 0;
          QUEUE,  FCR2JQ;
          SEIZE,  3: Jeff, 1;
          QUEUE,  FCR2HQ;
          SEIZE,  3: HotWater, 1;
          DELAY:  UNIF(4, 5, 6);
          RELEASE: Jeff, 1: HotWater, 1;
          DELAY:  SanVol / ColdRate;                  6 F1 cold water + sanitizer
          DELAY:  SanSit;                             7 sanitizer contact
          DELAY:  SanXfer;                            8 pump sanitizer to F2
          ASSIGN: CleanFerm = CleanFerm + 2;          both fermenters ready
          DISPOSE;

; Tun cleaning jobs

MTClean   ASSIGN: TunIdx = 1:  LeaveMT1 = TNOW:  NEXT(TunClean);
BTClean   ASSIGN: TunIdx = 2;
          QUEUE,  TeardownQ;
          SEIZE,  3: Jeff, 1;
          DELAY:  TeardownT;
          RELEASE: Jeff, 1:   NEXT(TunClean);
 
TunClean  QUEUE,  TCFillQ;                            1 fill to 5 in (15.8 gal)
          SEIZE,  3: HotWater, 1;
          DELAY:  CleanVol / FillRate;
          RELEASE: HotWater, 1;
          QUEUE,  TCScrub1Q;                          2 scrub
          SEIZE,  3: Jeff, 1;
          DELAY:  ScrubT;
          RELEASE: Jeff, 1;
          DELAY:  TunSoak;                            3 OxiClean soak
          QUEUE,  TCScrub2Q;                          4 scrub
          SEIZE,  3: Jeff, 1;
          DELAY:  ScrubT;
          RELEASE: Jeff, 1;
          DELAY:  CleanVol / DrainRate;               5 drain
          BRANCH, 1: If, TunIdx == 1, RelMT, Yes:
                     Else, RelBT, Yes;
RelMT     ASSIGN: MTCleanT = TNOW;
          RELEASE: MashTun, 1;
          DISPOSE;
RelBT     RELEASE: BoilTun, 1;
          DISPOSE;
 
END;
