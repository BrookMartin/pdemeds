*! pdemeds_test.do  1.0.0  20nov2026
/*==============================================================================
  Synthetic test suite for pdemeds, pbmeds and pdemme.
  Uses only made-up data built below (no Medicare data).

    . net get pdemeds, from("https://raw.githubusercontent.com/BrookMartin/pdemeds/main/")
    . do pdemeds_test.do

  Every check prints "pass" or "FAIL"; the do-file stops with an error at the
  end if any check failed. Expected values are worked out by hand in the
  comments next to each check.

  Synthetic cohort (one row per surgical episode, id = link):
    link 1  bene A  admitted 01mar2018  opioids pre and post, NSAIDs incl.
                                        topical gel, adalimumab (PDE),
                                        infliximab/rituximab/ESI (Part B)
    link 2  bene B  admitted 15jun2018  apomorphine, buprenorphine/naloxone,
                                        buprenorphine patch
    link 3  bene C  admitted 01jan2019  no claims at all
    link 4  bene D  admitted 01feb2018  first episode  -- the same claims are
    link 5  bene D  admitted 01aug2018  second episode -- re-anchored per episode
==============================================================================*/
version 16
clear all
set more off

foreach c in pdemeds pbmeds pdemme {
    capture which `c'
    if _rc {
        di as err "`c'.ado not found on the adopath; install the package first"
        exit 111
    }
}

global T_tests 0
global T_fails 0
capture program drop _chk
program define _chk
    args label cond
    capture assert `cond'
    if _rc {
        di as err "  FAIL: `label'"
        global T_fails = $T_fails + 1
    }
    else di as txt "  pass: `label'"
    global T_tests = $T_tests + 1
end

tempfile cohort pa pb lb op def ex

/*------------------------------------------------------------------------------
  1. pdemme: MME per dispensed unit
------------------------------------------------------------------------------*/
di as txt _n "{hline 70}" _n "1. pdemme" _n "{hline 70}"
clear
input str44 gnn str14 str double e22 double e16
"HYDROCODONE BITARTRATE/ACETAMINOPHEN" "10MG-325MG"   10    10
"HYDROCODONE BITARTRATE/ACETAMINOPHEN" "7.5-325/15"   0.5   0.5
"ACETAMINOPHEN WITH CODEINE"           "300-30 MG"    4.5   4.5
"OXYCODONE HCL"                        "100 MG/5ML"   30    30
"METHADONE HCL"                        "10 MG/5 ML"   9.4   6
"TRAMADOL HCL"                         "50 MG"        10    5
"HYDROMORPHONE HCL"                    "8 MG"         40    32
"FENTANYL"                             "25 MCG/HR"    180   180
"FENTANYL CITRATE"                     "200 MCG"      26    26
"BUPRENORPHINE"                        "5 MCG/HR"     63    63
"BUPRENORPHINE HCL"                    "150 MCG"      4.5   4.5
"MORPHINE SULFATE/NALTREXONE"          "20MG-0.8MG"   20    20
"BUPRENORPHINE HCL/NALOXONE HCL"       "8 MG-2 MG"    .     .
"APOMORPHINE HCL"                      "30 MG/3 ML"   .     .
"MELOXICAM"                            "15 MG"        .     .
end
* e22/e16 = expected MME per unit with cdc2022 / cdc2016 factors, e.g.
*   APAP/codeine 300-30: codeine is 2nd ingredient -> 30 mg x 0.15 = 4.5
*   methadone 10 mg/5 mL = 2 mg/mL x 4.7 (2022) or x 3 (2016)
*   fentanyl 25 mcg/hr patch = 25 x 2.4 x 3 days = 180
*   buprenorphine 5 mcg/hr patch = 5 x 1.8 x 7 days = 63
pdemme, gnn(gnn) strength(str) generate(mu22) cf(cdc2022) ingredient(ing) reason(why)
pdemme, gnn(gnn) strength(str) generate(mu16) cf(cdc2016)
gen byte ok22 = cond(missing(e22), missing(mu22), abs(mu22 - e22) < 1e-6)
gen byte ok16 = cond(missing(e16), missing(mu16), abs(mu16 - e16) < 1e-6)
forvalues i = 1/`=_N' {
    local lbl = gnn[`i'] + " " + str[`i']
    _chk "pdemme cdc2022: `lbl'" "ok22[`i'] == 1"
    _chk "pdemme cdc2016: `lbl'" "ok16[`i'] == 1"
}
_chk "pdemme: buprenorphine MOUD reason" `"why[13] == "buprenorphine mg (MOUD): not assigned""'
_chk "pdemme: apomorphine is not an opioid" `"ing[14] == """'
_chk "pdemme: codeine detected"             `"ing[3] == "CODEINE""'

/*------------------------------------------------------------------------------
  2. Synthetic cohort and claim files
------------------------------------------------------------------------------*/
clear
input str4 bene_id byte link str9 adm str9 dis
"A" 1 "01mar2018" "04mar2018"
"B" 2 "15jun2018" "18jun2018"
"C" 3 "01jan2019" "03jan2019"
"D" 4 "01feb2018" "05feb2018"
"D" 5 "01aug2018" "03aug2018"
end
gen indexadm = date(adm, "DMY")
gen indexdis = date(dis, "DMY")
format indexadm indexdis %td
drop adm dis
save `cohort'

* ---- pharmacy claim file (Medicare Part D variable names). rel = days from the bene's FIRST admission
clear
input str4 bene_id int rel str44 gnn str24 bn str12 str qty_dspnsd_num days_suply_num str11 prod_srvc_id
"A"  -10 "OXYCODONE HCL/ACETAMINOPHEN"          "PERCOCET"               "5 MG-325MG"  30  5 "00000000001"
"A"    2 "HYDROCODONE BITARTRATE/ACETAMINOPHEN" "NORCO"                  "10MG-325MG"  20  5 "00000000002"
"A"   20 "METHADONE HCL"                        "METHADONE HCL"          "10 MG/5 ML" 100 10 "00000000003"
"A"   -5 "DICLOFENAC SODIUM"                    "VOLTAREN"               "1 %"        100 30 "00000000004"
"A"  -30 "MELOXICAM"                            "MELOXICAM"              "15 MG"       30 30 "00000000005"
"A" -100 "MELOXICAM"                            "MELOXICAM"              "15 MG"       30 30 "00000000005"
"A"  -30 "ADALIMUMAB"                           "HUMIRA PEN"             "40MG/0.8ML"   2 28 "00000000006"
"B"  -20 "APOMORPHINE HCL"                      "APOKYN"                 "30 MG/3 ML"   3 30 "00000000007"
"B"  -15 "BUPRENORPHINE HCL/NALOXONE HCL"       "BUPRENORPHINE-NALOXONE" "8 MG-2 MG"   14  7 "00000000008"
"B"   10 "BUPRENORPHINE"                        "BUTRANS"                "5 MCG/HR"     4 28 "00000000009"
"D"  164 "OXYCODONE HCL"                        "OXYCODONE HCL"          "10 MG"       10  5 "00000000010"
end
gen srvc_dt = rel + cond(bene_id == "A", td(01mar2018), cond(bene_id == "B", td(15jun2018), td(01feb2018)))
format srvc_dt %td
drop rel
* two files; the second uses UPPER-CASE variable names (matching is case-insensitive)
preserve
    keep if srvc_dt < td(01jul2018)
    save `pa'
restore
keep if srvc_dt >= td(01jul2018)
rename *, upper
save `pb'

* ---- professional claim lines (Medicare carrier-line names)
clear
input str4 bene_id int rel str5 hcpcs_cd line_srvc_cnt str7 line_icd_dgns_cd
"A"  -60 "J1745" 30 "M0579"
"A"  -60 "J1745" 20 "M0579"
"A"  -20 "J1745" 50 "M0579"
"A"  -40 "62323"  1 "M5416"
"A"  -40 "J3301"  4 "M5416"
"B"   -5 "99213"  1 "I10"
"D"  164 "J0897" 60 "M810"
end
gen line_1st_expns_dt = rel + cond(bene_id == "A", td(01mar2018), cond(bene_id == "B", td(15jun2018), td(01feb2018)))
format line_1st_expns_dt %td
drop rel
save `lb'

* ---- facility claim lines (Medicare outpatient revenue-center names: different date/unit variables)
clear
input str4 bene_id int rel str5 hcpcs_cd rev_cntr_unit_cnt
"A" -150 "Q5115" 50
end
gen rev_cntr_dt = rel + td(01mar2018)
format rev_cntr_dt %td
drop rel
save `op'

/*------------------------------------------------------------------------------
  3. pdemeds
------------------------------------------------------------------------------*/
di as txt _n "{hline 70}" _n "3. pdemeds" _n "{hline 70}"
use `cohort', clear
pdemeds, files("`pa'" "`pb'") id(link) index(indexadm)                        ///
    classes(opioid opioid_moud nsaid nsaid_topical dmard_bio)                  ///
    windows(pre:-90/-1 post:0/90 pre180:-180/-1)                               ///
    stats(any n days first cov pdc mme mmeday mmemax)

* link 1: oxycodone/APAP day -10: 30 tabs x 5 mg x 1.5 = 225 MME
_chk "opioid pre any (link 1)"        "opioid_pre_any == 1 if link == 1"
_chk "opioid pre n (link 1)"          "opioid_pre_n == 1 if link == 1"
_chk "opioid pre MME = 225"           "abs(opioid_pre_mme - 225) < 1e-6 if link == 1"
_chk "opioid pre MME/day = 225/90"    "abs(opioid_pre_mmeday - 2.5) < 1e-6 if link == 1"
* post: hydrocodone day 2 (20 x 10 = 200) + methadone day 20 (100 mL x 9.4 = 940)
_chk "opioid post n = 2"              "opioid_post_n == 2 if link == 1"
_chk "opioid post MME = 1140"         "abs(opioid_post_mme - 1140) < 1e-6 if link == 1"
_chk "opioid post MME/day = 1140/91"  "abs(opioid_post_mmeday - 1140/91) < 1e-6 if link == 1"
_chk "opioid post max daily = 94"     "abs(opioid_post_mmemax - 94) < 1e-6 if link == 1"
* NSAIDs: gel (1 %) excluded; meloxicam day -30 in pre, day -100 only in pre180
_chk "nsaid pre n = 1 (gel excluded)" "nsaid_pre_n == 1 if link == 1"
_chk "nsaid pre days = 30"            "nsaid_pre_days == 30 if link == 1"
_chk "nsaid pre first = -30"          "nsaid_pre_first == -30 if link == 1"
_chk "nsaid pre180 n = 2"             "nsaid_pre180_n == 2 if link == 1"
_chk "topical NSAID flagged"          "nsaid_topical_pre_any == 1 if link == 1"
* covered days in pre (-90..-1): fill at -100 covers -100..-71 -> 20 days in
* window (carry-over); fill at -30 covers -30..-1 -> 30 days. Total 50.
_chk "nsaid pre covered days = 50"    "nsaid_pre_cov == 50 if link == 1"
_chk "nsaid pre PDC = 50/90"          "abs(nsaid_pre_pdc - 50/90) < 1e-6 if link == 1"
_chk "adalimumab (PDE) pre"           "dmard_bio_pre_any == 1 & dmard_bio_pre_first == -30 if link == 1"
* link 2: apomorphine is not an opioid; buprenorphine/naloxone is MOUD only
_chk "apomorphine/bup-nlx not opioid" "opioid_pre_any == 0 if link == 2"
_chk "bup-nlx in opioid_moud"         "opioid_moud_pre_any == 1 if link == 2"
* Butrans 5 mcg/hr, 4 patches x 63 = 252 MME over 28 days = 9/day
_chk "Butrans post MME = 252"         "abs(opioid_post_mme - 252) < 1e-6 if link == 2"
_chk "Butrans max daily = 9"          "abs(opioid_post_mmemax - 9) < 1e-6 if link == 2"
* link 3: no claims -> zeros, missing first-fill day
_chk "no claims -> 0"                 "opioid_pre_any == 0 & nsaid_pre_n == 0 & opioid_pre_mme == 0 if link == 3"
_chk "no claims -> first missing"     "missing(nsaid_pre_first) if link == 3"
* bene D: the 15jul2018 fill is day +164 for link 4 and day -17 for link 5
_chk "episode re-anchoring (link 4)"  "opioid_pre_any == 0 & opioid_post_any == 0 if link == 4"
_chk "episode re-anchoring (link 5)"  "opioid_pre_any == 1 & abs(opioid_pre_mme - 150) < 1e-6 if link == 5"
_chk "returned N_claims"              "r(N_claims) > 0"

* ---- cdc2016 factors: methadone 100 mL x 2 mg x 3 = 600; + hydrocodone 200
pdemeds, files("`pa'" "`pb'") id(link) index(indexadm) classes(opioid)       ///
    windows(post:0/90) stats(mme) mmecf(cdc2016) prefix(v16_) noreport
_chk "cdc2016 post MME = 800"         "abs(v16_opioid_post_mme - 800) < 1e-6 if link == 1"

* ---- user-defined class through deffile()
file open fh using "`def'", write replace
file write fh "class,label,include,exclude" _n
file write fh `"mycls,"My meloxicam class","MELOXICAM","""' _n
file close fh
pdemeds, files("`pa'" "`pb'") id(link) index(indexadm) deffile("`def'")      ///
    classes(mycls) windows(pre:-90/-1) stats(any n) prefix(d_) noreport
_chk "deffile() class"                "d_mycls_pre_any == 1 & d_mycls_pre_n == 1 if link == 1"

* ---- replace option and enrolled()
gen byte partd = link != 2
pdemeds, files("`pa'" "`pb'") id(link) index(indexadm) deffile("`def'")      ///
    classes(mycls) windows(pre:-90/-1) stats(any n) prefix(d_)                ///
    enrolled(partd) replace noreport
_chk "replace + enrolled(): missing if not enrolled" "missing(d_mycls_pre_any) if link == 2"
_chk "replace + enrolled(): kept if enrolled"        "d_mycls_pre_any == 1 if link == 1"

* ---- utilities
pdemeds, listclasses
pdemeds, exportclasses("`ex'")
preserve
    import delimited using "`ex'", clear varnames(1)
    _chk "exportclasses: library has >= 40 classes" "_N >= 40"
restore

/*------------------------------------------------------------------------------
  4. pbmeds (+ combine with the pdemeds results above)
------------------------------------------------------------------------------*/
di as txt _n "{hline 70}" _n "4. pbmeds" _n "{hline 70}"
pbmeds, listclasses
pbmeds, files("`lb'" "`op'") id(link) index(indexadm)                         ///
    classes(dmard_bio dmard_rtx esi cortico_inj denosumab)                     ///
    windows(pre:-90/-1 post:0/90 pre180:-180/-1)                               ///
    stats(any n first last units) combine(rx_)

* link 1: infliximab lines on day -60 (two lines, one day) and day -20
_chk "infliximab pre days = 2"        "pb_dmard_bio_pre_n == 2 if link == 1"
_chk "infliximab pre units = 100"     "pb_dmard_bio_pre_units == 100 if link == 1"
_chk "infliximab pre first/last"      "pb_dmard_bio_pre_first == -60 & pb_dmard_bio_pre_last == -20 if link == 1"
* rituximab biosimilar Q5115 on day -150 (outpatient file, rev_cntr_dt)
_chk "outpatient file read (pre180)"  "pb_dmard_bio_pre180_n == 3 & pb_dmard_bio_pre180_units == 150 if link == 1"
_chk "rituximab pre180 only"          "pb_dmard_rtx_pre180_any == 1 & pb_dmard_rtx_pre_any == 0 if link == 1"
_chk "ESI procedure (62323)"          "pb_esi_pre_any == 1 if link == 1"
_chk "injectable steroid units = 4"   "pb_cortico_inj_pre_units == 4 if link == 1"
_chk "office visit not a drug"        "pb_dmard_bio_pre_any == 0 & pb_esi_pre_any == 0 if link == 2"
_chk "denosumab re-anchored (link 5)" "pb_denosumab_pre_any == 1 if link == 5"
_chk "denosumab re-anchored (link 4)" "pb_denosumab_post_any == 0 if link == 4"
_chk "no claims -> 0 (link 3)"        "pb_dmard_bio_pre_n == 0 & pb_esi_pre_any == 0 if link == 3"
* combine(): PDE adalimumab fill (day -30) + 2 Part B days
_chk "combined any"                   "rx_dmard_bio_pre_any == 1 if link == 1"
_chk "combined n = 1 + 2"             "rx_dmard_bio_pre_n == 3 if link == 1"
_chk "combined first = min(-30, -60)" "rx_dmard_bio_pre_first == -60 if link == 1"
_chk "combined pre180 first = -150"   "rx_dmard_bio_pre180_first == -150 if link == 1"
_chk "returned N_lines"               "r(N_lines) > 0"

/*------------------------------------------------------------------------------
  Summary
------------------------------------------------------------------------------*/
di as txt _n "{hline 70}"
di as txt "pdemeds test suite: " as res $T_tests as txt " checks, " ///
    as res $T_fails as txt " failed"
di as txt "{hline 70}"
if $T_fails > 0 {
    di as err "Some checks failed: see FAIL lines above."
    exit 9
}
di as res "All checks passed."
