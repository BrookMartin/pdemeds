*! pdemme 1.0.0  20nov2026
*! Brook I. Martin, PhD MPH, University of Utah
*! https://github.com/BrookMartin/pdemeds
*! Morphine milligram equivalents (MME) per dispensed unit, from pharmacy
*! claims generic name (gnn) and strength text (str).
*!
*! Syntax:
*!   pdemme , gnn(varname) strength(varname) generate(newvar)
*!            [ cf(cdc2022|cdc2016) ingredient(newvar) reason(newvar)
*!              bupoud(#) replace ]
*!
*! generate()   MME per dispensed unit (per tablet/capsule, per mL of liquid,
*!              per transdermal patch, per buccal film/lozenge, per spray).
*!              Claim total MME  = qty_dspnsd_num * generate
*!              Claim daily MME  = qty_dspnsd_num * generate / days_suply_num
*! cf()         conversion-factor set. cdc2022 (default): hydromorphone 5,
*!              methadone 4.7, tramadol 0.2 (CDC 2022 guideline).
*!              cdc2016: hydromorphone 4, methadone 3, tramadol 0.1 (CDC 2016 /
*!              CDC NDC-MME file values).  All other factors are identical.
*! ingredient() opioid ingredient detected (blank if not an opioid)
*! reason()     "ok" or why MME could not be assigned -- review these.
*! bupoud(#)    MME per mg for buprenorphine products dosed in mg (sublingual /
*!              injectable MOUD formulations). Default: not assigned, per CDC
*!              guidance that MME should not be calculated for buprenorphine
*!              used for opioid use disorder.
*!
*! Run it on a file of DISTINCT gnn x str combinations (fast), then merge
*! the result back onto claims m:1 on gnn str.
*!
*! Parsing rules (str has spaces removed first):
*!   - opioid position in a combination product = position of the opioid in
*!     gnn (components split on "/", "-", " WITH "); the matching hyphen-
*!     separated number in str is used, e.g. ACETAMINOPHEN WITH CODEINE,
*!     "300-30 MG" -> 30 mg codeine.
*!   - liquids: "A MG/B ML", "A MG/ML", or truncated "A-B/15" -> A/B per mL
*!   - transdermal ("MCG/HR"): fentanyl  = mcg/hr x 2.4 x 3 days per patch
*!                             buprenorphine = mcg/hr x 1.8 x 7 days per patch
*!   - fentanyl buccal/SL/lozenge (mcg) x 0.13; nasal spray (mcg) x 0.16
*!   - buprenorphine buccal film (mcg, e.g. Belbuca) x 0.03
*!   - injectables expressed as MCG/ML (fentanyl) are not assigned.
*! Anything unparsed is left missing with a reason so it can be supplied via
*! an NDC-level crosswalk (see pdemeds, mmefile()).

program define pdemme, rclass
    version 16
    syntax , GNN(varname string) STRength(varname string) GENerate(name) ///
        [ CF(string) INGredient(name) REASon(name) BUPoud(real -1) REPLACE ]

    if "`cf'" == "" local cf cdc2022
    local cf = lower("`cf'")
    if !inlist("`cf'", "cdc2022", "cdc2016") {
        di as err "cf() must be cdc2022 or cdc2016"
        exit 198
    }
    foreach v in `generate' `ingredient' `reason' {
        if "`replace'" != "" capture drop `v'
        confirm new variable `v'
    }

    * conversion factors, MME per mg (oral unless noted)
    local fac HYDROCODONE 1 OXYCODONE 1.5 MORPHINE 1 OXYMORPHONE 3 CODEINE 0.15 ///
              DIHYDROCODEINE 0.25 TAPENTADOL 0.4 MEPERIDINE 0.1 LEVORPHANOL 11  ///
              PENTAZOCINE 0.37 OPIUM 1
    if "`cf'" == "cdc2022" local fac `fac' HYDROMORPHONE 5 METHADONE 4.7 TRAMADOL 0.2
    else                   local fac `fac' HYDROMORPHONE 4 METHADONE 3   TRAMADOL 0.1

    tempvar g s numpart after vol pos n cfv mu why ing mcg pre nslash
    quietly {
        * ---- normalise text
        gen str244 `g' = " " + upper(`gnn') + " "
        replace `g' = subinstr(`g', " WITH ", "/", .)
        replace `g' = subinstr(`g', "-", "/", .)
        gen str244 `s' = subinstr(upper(`strength'), " ", "", .)
        gen byte `mcg' = strpos(`s', "MCG") > 0

        * ---- opioid ingredient (names that contain other names are tested first)
        gen str16 `ing' = ""
        foreach i in DIHYDROCODEINE BENZHYDROCODONE HYDROCODONE OXYCODONE        ///
                     HYDROMORPHONE OXYMORPHONE LEVORPHANOL CODEINE FENTANYL       ///
                     BUPRENORPHINE METHADONE MEPERIDINE TAPENTADOL TRAMADOL       ///
                     PENTAZOCINE BUTORPHANOL OPIUM MORPHINE {
            replace `ing' = "`i'" if `ing' == "" & strpos(`g', "`i'")
        }
        replace `ing' = "" if `ing' == "MORPHINE" & strpos(`g', "APOMORPHINE")

        * ---- position of the opioid among the product's ingredients
        gen str244 `pre' = substr(`g', 1, strpos(`g', `ing') - 1) if `ing' != ""
        gen int `nslash' = strlen(`pre') - strlen(subinstr(`pre', "/", "", .))
        gen int `pos' = 1 + `nslash' if `ing' != ""

        * ---- split strength into numeric part and denominator
        gen str244 `numpart' = cond(strpos(`s', "/"), substr(`s', 1, strpos(`s', "/") - 1), `s')
        gen str244 `after'   = cond(strpos(`s', "/"), substr(`s', strpos(`s', "/") + 1, .), "")
        * "5MG/325MG" style: slash separates ingredients, not a volume
        replace `numpart' = `numpart' + "-" + `after' if strpos(`after', "MG") & !strpos(`after', "ML")
        replace `after'   = "" if strpos(`after', "MG") & !strpos(`after', "ML")
        replace `numpart' = subinstr(subinstr(subinstr(`numpart', "MCG", "", .), "MG", "", .), "%", "", .)

        gen double `vol' = 1
        replace `vol' = real(subinstr(`after', "ML", "", .)) if strpos(`after', "ML") & `after' != "ML"
        replace `vol' = real(`after') if `after' != "" & !missing(real(`after'))
        replace `vol' = 1 if missing(`vol') | `vol' <= 0

        * ---- k-th hyphen-separated number
        gen double `n' = .
        forvalues k = 1/5 {
            local pat "^"
            forvalues j = 1/`=`k'-1' {
                local pat "`pat'[0-9.]+-"
            }
            local pat "`pat'([0-9]*[.]?[0-9]+)"
            replace `n' = real(ustrregexs(1)) if `pos' == `k' & ustrregexm(`numpart', "`pat'")
        }

        * ---- conversion factor
        gen double `cfv' = .
        tokenize `fac'
        while "`1'" != "" {
            replace `cfv' = `2' if `ing' == "`1'"
            macro shift 2
        }

        * ---- MME per dispensed unit
        gen double `mu' = `n' / `vol' * `cfv' * cond(`mcg', 0.001, 1) ///
            if !missing(`cfv') & !inlist(`ing', "FENTANYL", "BUPRENORPHINE")

        * fentanyl
        replace `mu' = `n' * 7.2  if `ing' == "FENTANYL" & strpos(`s', "/HR")
        replace `mu' = `n' * 0.16 if `ing' == "FENTANYL" & missing(`mu') & `mcg' & ///
                                     (strpos(`s', "SPR") | strpos(`s', "ACT"))
        replace `mu' = `n' * 0.13 if `ing' == "FENTANYL" & missing(`mu') & `mcg' & ///
                                     !strpos(`s', "ML") & !strpos(`s', "/HR")
        * buprenorphine
        replace `mu' = `n' * 12.6 if `ing' == "BUPRENORPHINE" & strpos(`s', "/HR")
        replace `mu' = `n' * 0.03 if `ing' == "BUPRENORPHINE" & missing(`mu') & `mcg' & ///
                                     !strpos(`s', "ML")
        if `bupoud' >= 0 {
            replace `mu' = `n' / `vol' * `bupoud' if `ing' == "BUPRENORPHINE" & missing(`mu') & !`mcg'
        }

        * ---- reason codes
        gen str48 `why' = ""
        replace `why' = "not an opioid"        if `ing' == ""
        replace `why' = "ok"                   if !missing(`mu')
        replace `why' = "buprenorphine mg (MOUD): not assigned" ///
            if `why' == "" & `ing' == "BUPRENORPHINE" & !`mcg'
        replace `why' = "injectable mcg/mL: not assigned" ///
            if `why' == "" & `ing' == "FENTANYL" & strpos(`s', "ML")
        replace `why' = "no conversion factor for ingredient" ///
            if `why' == "" & missing(`cfv') & !inlist(`ing', "FENTANYL", "BUPRENORPHINE")
        replace `why' = "strength not parsed" if `why' == ""

        gen double `generate' = `mu'
        label variable `generate' "MME per dispensed unit (`cf')"
        if "`ingredient'" != "" {
            gen str16 `ingredient' = `ing'
            label variable `ingredient' "Opioid ingredient (pdemme)"
        }
        if "`reason'" != "" {
            gen str48 `reason' = `why'
            label variable `reason' "MME assignment note (pdemme)"
        }
        count if `ing' != ""
        local nop = r(N)
        count if `ing' != "" & !missing(`mu')
        local nok = r(N)
    }
    di as txt "pdemme: " as res `nop' as txt " opioid rows; MME assigned for " ///
        as res `nok' as txt " (cf = `cf')"
    if `nop' > `nok' di as txt `"        review rows where the reason variable is not "ok""'
    return scalar N_opioid  = `nop'
    return scalar N_ok      = `nok'
    return local  cf        "`cf'"
end
