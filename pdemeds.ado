*! pdemeds 1.0.0  16nov2026
*! Medication-class exposure from pharmacy claims (e.g. Medicare PDE files) claims in
*! user-defined windows around an index date. Works with any cohort.
*!
*! Quick start
*!   pdemeds, listclasses                       // built-in class library
*!   pdemeds, exportclasses(myclasses.csv)      // edit / extend, pass back via deffile()
*!   use cohort, clear                          // one row per episode
*!   pdemeds, files(PDE16 PDE17 PDE18) id(link) index(indexadm)   ///
*!            classes(opioid nsaid gabapentinoid)                  ///
*!            windows(pre:-90/-1 post:0/90 yr:0/365)               ///
*!            stats(any n days first mme mmeday pdc)
*!
*! Creates  <prefix><class>_<window>_<stat>  for every class x window x stat.
*! See help pdemeds.  Requires pdemme.ado for MME statistics.

program define pdemeds, rclass
    version 16
    syntax [, FILEs(string asis) ID(varname) INDEX(varname numeric)          ///
        PERSON(name) CLASSes(string) DEFfile(string) WINdows(string)        ///
        STATs(string) PREfix(string) ENROLLed(varname numeric)              ///
        SRVCdt(name) QTY(name) DAYS(name) GNN(name) BN(name)                ///
        STRength(name) NDC(name) FORM(name)                                 ///
        MMECF(string) MMEFILE(string) MMEClasses(string) BUPoud(real -1)    ///
        CARRYover(integer 180) SAVEclaims(string) LISTclasses               ///
        EXPORTclasses(string) REPLACE NOREPort ]

    *--------------------------------------------------------------------*
    * utility modes: list / export the class library
    *--------------------------------------------------------------------*
    if "`listclasses'" != "" | `"`exportclasses'"' != "" {
        preserve
        quietly _pdemeds_lib
        if `"`deffile'"' != "" quietly _pdemeds_deffile `"`deffile'"'
        if "`listclasses'" != "" {
            di as txt _n "{hline 78}"
            di as txt %-16s "class" "  label"
            di as txt "{hline 78}"
            forvalues k = 1/`=_N' {
                di as res %-16s class[`k'] as txt "  " label[`k']
            }
            di as txt "{hline 78}"
            di as txt "regexes: pdemeds, exportclasses(file.csv)"
        }
        if `"`exportclasses'"' != "" {
            export delimited class label include exclude using `"`exportclasses'"', replace quote
            di as txt `"class definitions written to `exportclasses'"'
        }
        restore
        exit
    }

    *--------------------------------------------------------------------*
    * defaults and checks
    *--------------------------------------------------------------------*
    if `"`files'"' == "" | "`id'" == "" | "`index'" == "" {
        di as err "files(), id() and index() are required"
        exit 198
    }
    if "`person'"   == "" local person   bene_id
    if "`srvcdt'"   == "" local srvcdt   srvc_dt
    if "`qty'"      == "" local qty      qty_dspnsd_num
    if "`days'"     == "" local days     days_suply_num
    if "`gnn'"      == "" local gnn      gnn
    if "`bn'"       == "" local bn       bn
    if "`strength'" == "" local strength str
    if "`ndc'"      == "" local ndc      prod_srvc_id
    if "`mmecf'"    == "" local mmecf    cdc2022
    if "`mmeclasses'" == "" local mmeclasses opioid
    if `"`windows'"' == "" local windows "pre:-90/-1 post:0/90"
    if "`stats'"    == "" local stats    "any n"
    local stats = lower("`stats'")
    local stats : list uniq stats

    local okstats any n days qty first last cov pdc mme mmeday mmemax
    foreach s of local stats {
        if !`: list s in okstats' {
            di as err "stats(): `s' not allowed. Choose from: `okstats'"
            exit 198
        }
    }
    local want_cov = `: list posof "cov" in stats' | `: list posof "pdc" in stats'
    local want_mme = `: list posof "mme" in stats' | `: list posof "mmeday" in stats' | ///
                     `: list posof "mmemax" in stats'
    local carry = cond(`want_cov', `carryover', 0)
    if `want_mme' {
        capture which pdemme
        if _rc {
            di as err "MME statistics need pdemme.ado on the adopath"
            exit 111
        }
    }

    * ---- windows  name:lo/hi
    local wnames
    local lomin .
    local himax .
    foreach w of local windows {
        if !ustrregexm(`"`w'"', "^([A-Za-z][A-Za-z0-9_]*):(-?[0-9]+)/(-?[0-9]+)") {
            di as err `"windows(): "`w'" is not of the form name:lo/hi (e.g. pre:-90/-1)"'
            exit 198
        }
        local nm = ustrregexs(1)
        local lo = ustrregexs(2)
        local hi = ustrregexs(3)
        if `lo' > `hi' {
            di as err "windows(): `nm' has lo > hi"
            exit 198
        }
        if `: list nm in wnames' {
            di as err "windows(): `nm' given twice"
            exit 198
        }
        local wlo_`nm' `lo'
        local whi_`nm' `hi'
        local wnames `wnames' `nm'
        local lomin = min(`lomin', `lo')
        local himax = max(`himax', `hi')
    }

    *--------------------------------------------------------------------*
    * class definitions
    *--------------------------------------------------------------------*
    preserve
    quietly {
        _pdemeds_lib
        if `"`deffile'"' != "" _pdemeds_deffile `"`deffile'"'
        if !inlist(lower("`classes'"), "", "all") {
            gen byte _sel = 0
            foreach c of local classes {
                count if class == "`c'"
                if r(N) == 0 {
                    noisily di as err "class `c' is not defined (see: pdemeds, listclasses)"
                    exit 111
                }
                replace _sel = 1 if class == "`c'"
            }
            keep if _sel
        }
        local K = _N
        local allcls
        forvalues k = 1/`K' {
            local cls`k' = class[`k']
            local lab`k' = label[`k']
            local inc`k' = include[`k']
            local exc`k' = exclude[`k']
            local allcls `allcls' `cls`k''
        }
    }
    restore
    if `K' == 0 {
        di as err "no classes selected"
        exit 198
    }

    local mmecl : list mmeclasses & allcls
    if `want_mme' & "`mmecl'" == "" {
        di as txt "note: no selected class is listed in mmeclasses(`mmeclasses'); MME stats skipped"
        local mmestats mme mmeday mmemax
        local stats : list stats - mmestats
        local want_mme 0
    }

    * ---- output names
    local outvars
    forvalues k = 1/`K' {
        local isme : list cls`k' in mmecl
        foreach w of local wnames {
            foreach s of local stats {
                if inlist("`s'", "mme", "mmeday", "mmemax") & !`isme' continue
                local v `prefix'`cls`k''_`w'_`s'
                if strlen("`v'") > 32 {
                    di as err "variable name `v' exceeds 32 characters; shorten prefix(), class or window names"
                    exit 198
                }
                local outvars `outvars' `v'
            }
        }
    }

    *--------------------------------------------------------------------*
    * cohort keys
    *--------------------------------------------------------------------*
    preserve                                   // restored on error
    confirm variable `person'
    capture isid `id'
    if _rc {
        di as err "id(`id') does not uniquely identify observations"
        exit 459
    }
    foreach v of local outvars {
        capture confirm new variable `v'
        if _rc {
            if "`replace'" != "" drop `v'
            else {
                di as err "variable `v' already exists; specify replace"
                exit 110
            }
        }
    }
    tempfile cohort keys claims res mmexw
    quietly save `cohort'
    local kv `id' `person' `index'
    local kv : list uniq kv
    quietly {
        keep `kv'
        drop if missing(`index')
        rename `index' _pdm_index
        save `keys'
    }

    * optional NDC-level MME crosswalk
    if `want_mme' & `"`mmefile'"' != "" {
        quietly _pdemeds_mmefile `"`mmefile'"' `"`mmexw'"'
    }

    *--------------------------------------------------------------------*
    * read claim files once each
    *--------------------------------------------------------------------*
    local need `person' `srvcdt' `gnn' `strength' `qty' `days'
    if "`form'" != "" local need `need' `form'
    local opt `bn'
    if `"`mmefile'"' != "" local opt `opt' `ndc'
    local dk `gnn' `bn' `strength' `form'

    local have 0
    local nfiles 0
    foreach f of local files {
        local ++nfiles
        quietly describe using `"`f'"', varlist
        local avail `r(varlist)'
        local uselist
        local renlist
        local missopt
        foreach v in `need' `opt' {
            local hit
            foreach a of local avail {
                if lower("`a'") == lower("`v'") local hit `a'
            }
            if "`hit'" == "" {
                if `: list v in need' {
                    di as err `"variable `v' not found in `f'"'
                    exit 111
                }
                local missopt `missopt' `v'
                continue
            }
            local uselist `uselist' `hit'
            if "`hit'" != "`v'" local renlist `renlist' `hit' `v'
        }
        quietly {
            use `uselist' using `"`f'"', clear
            while "`renlist'" != "" {
                gettoken a renlist : renlist
                gettoken b renlist : renlist
                rename `a' `b'
            }
            foreach v of local missopt {
                gen str1 `v' = ""
            }
            joinby `person' using `keys'
            gen long _pdm_rel = `srvcdt' - _pdm_index
            keep if inrange(_pdm_rel, `lomin' - `carry', `himax')
            if _N == 0 continue

            * classify DISTINCT drug descriptions only
            tempfile cur dict
            save `cur'
            keep `dk'
            duplicates drop
            gen str2045 _pdm_U = " " + upper(`gnn') + " | " + upper(`bn') + " | " + upper(`strength') + " "
            if "`form'" != "" replace _pdm_U = _pdm_U + "| " + upper(`form') + " "
            forvalues k = 1/`K' {
                gen byte _c`k' = ustrregexm(_pdm_U, `"`inc`k''"')
                if `"`exc`k''"' != "" {
                    replace _c`k' = 0 if _c`k' & ustrregexm(_pdm_U, `"`exc`k''"')
                }
            }
            egen byte _pdm_hit = rowmax(_c*)
            keep if _pdm_hit == 1
            drop _pdm_hit _pdm_U
            if _N == 0 continue
            if `want_mme' {
                pdemme, gnn(`gnn') strength(`strength') generate(_pdm_mmeu) ///
                    cf(`mmecf') reason(_pdm_mmewhy) bupoud(`bupoud')
            }
            save `dict'
            use `cur', clear
            merge m:1 `dk' using `dict', keep(match) nogen
            if `have' == 0 save `claims'
            else {
                append using `claims'
                save `claims', replace
            }
            local have 1
        }
    }

    *--------------------------------------------------------------------*
    * claim-level measures and one collapse
    *--------------------------------------------------------------------*
    local covfiles
    local Nclaims 0
    if `have' {
        quietly {
            use `claims', clear
            local Nclaims = _N
            if `want_mme' {
                if `"`mmefile'"' != "" {
                    _pdemeds_ndc11 `ndc' _pdm_ndc
                    merge m:1 _pdm_ndc using `mmexw', keep(master match) nogen
                    replace _pdm_mmewhy = "ok (mmefile)" if !missing(mme_per_unit)
                    replace _pdm_mmeu = mme_per_unit if !missing(mme_per_unit)
                    drop mme_per_unit _pdm_ndc
                }
                gen double _pdm_mmetot = `qty' * _pdm_mmeu
                gen double _pdm_mmedd  = _pdm_mmetot / `days' if `days' > 0
            }

            local cmax
            local csum
            local cmin
            forvalues k = 1/`K' {
                local isme : list cls`k' in mmecl
                local j 0
                foreach w of local wnames {
                    local ++j
                    local b `prefix'`cls`k''_`w'
                    gen byte _i`k'_`j' = _c`k' & inrange(_pdm_rel, `wlo_`w'', `whi_`w'')
                    foreach s of local stats {
                        if "`s'" == "any" local cmax `cmax' `b'_any=_i`k'_`j'
                        if "`s'" == "n"   local csum `csum' `b'_n=_i`k'_`j'
                        if "`s'" == "days" {
                            gen double _d`k'_`j' = `days' if _i`k'_`j'
                            local csum `csum' `b'_days=_d`k'_`j'
                        }
                        if "`s'" == "qty" {
                            gen double _q`k'_`j' = `qty' if _i`k'_`j'
                            local csum `csum' `b'_qty=_q`k'_`j'
                        }
                        if inlist("`s'", "first", "last") {
                            capture confirm variable _f`k'_`j'
                            if _rc gen long _f`k'_`j' = _pdm_rel if _i`k'_`j'
                            if "`s'" == "first" local cmin `cmin' `b'_first=_f`k'_`j'
                            else                local cmax `cmax' `b'_last=_f`k'_`j'
                        }
                        if `isme' & inlist("`s'", "mme", "mmeday") {
                            capture confirm variable _m`k'_`j'
                            if _rc {
                                gen double _m`k'_`j' = _pdm_mmetot if _i`k'_`j'
                                local csum `csum' `b'_mme=_m`k'_`j'
                            }
                        }
                        if `isme' & "`s'" == "mmemax" {
                            gen double _x`k'_`j' = _pdm_mmedd if _i`k'_`j'
                            local cmax `cmax' `b'_mmemax=_x`k'_`j'
                        }
                    }
                }
            }
            save `claims', replace
        }

        * ---- report
        if "`noreport'" == "" {
            di as txt _n "{hline 60}"
            di as txt "pdemeds: " as res `nfiles' as txt " file(s), " ///
                as res `Nclaims' as txt " claims in any class (incl. carry-over)"
            di as txt %-16s "class" %14s "claims" %14s "ids"
            di as txt "{hline 60}"
            forvalues k = 1/`K' {
                tempvar inw tg
                quietly egen byte `inw' = rowmax(_i`k'_*)
                quietly count if `inw'
                local nc = r(N)
                quietly egen byte `tg' = tag(`id') if `inw'
                quietly count if `tg' == 1
                di as res %-16s "`cls`k''" %14.0fc `nc' %14.0fc r(N)
                drop `inw' `tg'
            }
            di as txt "{hline 60}"
            if `want_mme' {
                tempvar inme
                quietly gen byte `inme' = 0
                foreach c of local mmecl {
                    local kk : list posof "`c'" in allcls
                    quietly replace `inme' = 1 if _c`kk'
                }
                quietly count if `inme'
                local nme = r(N)
                quietly count if `inme' & missing(_pdm_mmetot)
                di as txt "MME (`mmecf'): " as res r(N) as txt " of " as res `nme' ///
                    as txt " claims in mmeclasses(`mmecl') have no MME"
                if r(N) > 0 {
                    tab _pdm_mmewhy if `inme', sort
                    di as txt "  supply an NDC crosswalk via mmefile() or check with saveclaims()"
                }
                drop `inme'
            }
        }

        * ---- optional claim-level output for auditing
        if `"`saveclaims'"' != "" {
            quietly {
                foreach p in _i _d _q _f _m _x {
                    capture drop `p'*
                }
                forvalues k = 1/`K' {
                    rename _c`k' c_`cls`k''
                }
                rename _pdm_rel days_from_index
                capture rename _pdm_mmeu  mme_per_unit
                capture rename _pdm_mmewhy mme_note
                capture rename _pdm_mmetot mme_total
                capture rename _pdm_mmedd  mme_daily
                save `"`saveclaims'"', replace
            }
            di as txt `"claim-level file saved: `saveclaims'"'
            quietly use `claims', clear
        }

        * ---- collapse to one row per id
        quietly {
            local cmd
            if "`cmax'" != "" local cmd `cmd' (max) `cmax'
            if "`csum'" != "" local cmd `cmd' (sum) `csum'
            if "`cmin'" != "" local cmd `cmd' (min) `cmin'
            if "`cmd'" != "" collapse `cmd', by(`id')
            else {
                keep `id'
                duplicates drop
            }
            save `res'
        }

        * ---- covered days (carry-over from earlier fills, no stockpiling)
        if `want_cov' {
            quietly forvalues k = 1/`K' {
                use `id' _pdm_rel `days' _c`k' if _c`k' using `claims', clear
                drop if missing(`days') | `days' <= 0
                keep if _pdm_rel <= `himax' & _pdm_rel + `days' - 1 >= `lomin'
                if _N == 0 continue
                gen long _row = _n
                expand `days'
                bysort _row: gen long _day = _pdm_rel + _n - 1
                keep if inrange(_day, `lomin', `himax')
                bysort `id' _day: keep if _n == 1
                local clist
                local j 0
                foreach w of local wnames {
                    local ++j
                    gen byte _w`j' = inrange(_day, `wlo_`w'', `whi_`w'')
                    local clist `clist' `prefix'`cls`k''_`w'_cov=_w`j'
                }
                collapse (sum) `clist', by(`id')
                tempfile cov`k'
                save `cov`k''
                local covfiles `"`covfiles' "`cov`k''""'
            }
        }
    }

    *--------------------------------------------------------------------*
    * assemble: cohort + results, zero-fill, derived stats, labels
    *--------------------------------------------------------------------*
    quietly {
        use `cohort', clear
        if `have' {
            merge 1:1 `id' using `res', keep(master match) nogen
            foreach cf of local covfiles {
                merge 1:1 `id' using `"`cf'"', keep(master match) nogen
            }
        }
        capture label define _pdm_yn 0 "no" 1 "yes"

        local sdesc_any    "any fill"
        local sdesc_n      "no. of fills"
        local sdesc_days   "days supplied"
        local sdesc_qty    "quantity dispensed"
        local sdesc_first  "first fill, days from index"
        local sdesc_last   "last fill, days from index"
        local sdesc_cov    "days covered"
        local sdesc_pdc    "proportion of days covered"
        local sdesc_mme    "total MME"
        local sdesc_mmeday "avg daily MME over window"
        local sdesc_mmemax "max daily MME of a fill"

        forvalues k = 1/`K' {
            local isme : list cls`k' in mmecl
            foreach w of local wnames {
                local b   `prefix'`cls`k''_`w'
                local len = `whi_`w'' - `wlo_`w'' + 1
                * base (zero-filled) measures, incl. helpers for derived stats
                foreach s in any n days qty mme cov {
                    local needit = `: list posof "`s'" in stats' > 0
                    if "`s'" == "mme" local needit = `isme' & ///
                        (`: list posof "mme" in stats' | `: list posof "mmeday" in stats')
                    if "`s'" == "cov" local needit = `want_cov'
                    if `needit' {
                        capture confirm variable `b'_`s'
                        if _rc gen double `b'_`s' = 0
                        replace `b'_`s' = 0 if missing(`b'_`s')
                    }
                }
                foreach s in first last {
                    if `: list posof "`s'" in stats' {
                        capture confirm variable `b'_`s'
                        if _rc gen long `b'_`s' = .
                    }
                }
                if `isme' & `: list posof "mmemax" in stats' {
                    capture confirm variable `b'_mmemax
                    if _rc gen double `b'_mmemax = .
                }
                * derived
                if `isme' & `: list posof "mmeday" in stats' gen double `b'_mmeday = `b'_mme / `len'
                if `: list posof "pdc" in stats' gen double `b'_pdc = `b'_cov / `len'
                if `isme' & `: list posof "mmeday" in stats' & !`: list posof "mme" in stats' drop `b'_mme
                if `want_cov' & !`: list posof "cov" in stats' drop `b'_cov
                * finish each requested variable
                foreach s of local stats {
                    if inlist("`s'", "mme", "mmeday", "mmemax") & !`isme' continue
                    local v `b'_`s'
                    replace `v' = . if missing(`index')
                    if "`enrolled'" != "" replace `v' = . if `enrolled' != 1
                    if inlist("`s'", "any", "n", "cov", "days") compress `v'
                    if "`s'" == "any" label values `v' _pdm_yn
                    local L = substr(`"`lab`k'' [`w' `wlo_`w''..`whi_`w'']: `sdesc_`s''"', 1, 80)
                    label variable `v' `"`L'"'
                }
            }
        }
    }
    restore, not

    di as txt "pdemeds: created " as res `: word count `outvars'' as txt " variables (" ///
        as res `K' as txt " classes x " as res `: word count `wnames'' as txt " windows)"
    return local varlist  "`outvars'"
    return local classes  "`allcls'"
    return local windows  `"`windows'"'
    return local stats    "`stats'"
    return scalar N_claims = `Nclaims'
end


*==========================================================================*
* helpers
*==========================================================================*

* 11-digit NDC string from a string or numeric NDC variable
program define _pdemeds_ndc11
    args src dst
    capture confirm string variable `src'
    if _rc gen str11 `dst' = string(`src', "%011.0f")
    else {
        gen str20 `dst' = ustrregexra(`src', "[^0-9]", "")
        replace `dst' = substr("00000000000" + `dst', -11, .)
    }
end

* NDC-level MME crosswalk -> tempfile with _pdm_ndc mme_per_unit
program define _pdemeds_mmefile
    args fn out
    if lower(substr(`"`fn'"', -4, .)) == ".csv" {
        import delimited using `"`fn'"', clear varnames(1) case(lower)
    }
    else use `"`fn'"', clear
    rename *, lower
    confirm variable ndc
    capture confirm variable mme_per_unit
    if _rc {
        confirm variable strength_per_unit mme_cf
        destring strength_per_unit mme_cf, replace force
        gen double mme_per_unit = strength_per_unit * mme_cf
    }
    else destring mme_per_unit, replace force
    _pdemeds_ndc11 ndc _pdm_ndc
    keep _pdm_ndc mme_per_unit
    drop if missing(mme_per_unit) | _pdm_ndc == ""
    duplicates drop
    capture isid _pdm_ndc
    if _rc {
        noisily di as txt "note: mmefile has conflicting values for some NDCs; first kept"
        bysort _pdm_ndc: keep if _n == 1
    }
    save `"`out'"'
end

* user definitions (CSV: class,label,include,exclude) replace/extend library
program define _pdemeds_deffile
    args fn
    tempfile lib usr
    save `lib'
    import delimited using `"`fn'"', clear varnames(1) case(lower) ///
        stringcols(_all) bindquote(strict)
    confirm variable class include
    capture confirm variable label
    if _rc gen label = ""
    capture confirm variable exclude
    if _rc gen exclude = ""
    keep class label include exclude
    replace class = strtrim(class)
    drop if class == ""
    forvalues i = 1/`=_N' {
        local c = class[`i']
        capture confirm name `c'
        if _rc | strlen("`c'") > 16 {
            noisily di as err "deffile(): class name `c' must be a valid Stata name of at most 16 characters"
            exit 198
        }
    }
    isid class
    save `usr'
    use `lib', clear
    merge 1:1 class using `usr', keep(master) nogen
    append using `usr'
end

* add one class to the library in memory
program define _pdm_add
    args class label include exclude
    local N = _N + 1
    set obs `N'
    replace class   = `"`class'"'   in `N'
    replace label   = `"`label'"'   in `N'
    replace include = `"`include'"' in `N'
    replace exclude = `"`exclude'"' in `N'
end

*--------------------------------------------------------------------------*
* Built-in class library.
* Regexes are matched (ICU, ustrregexm) against the upper-case string
*     " GNN | BN | STR | FORM "
* so ".*%" tests the strength, "[|] 10 ?MCG" tests the start of the strength,
* etc. FORM is included only if form() is given.
*--------------------------------------------------------------------------*
program define _pdemeds_lib
    clear
    gen str16   class   = ""
    gen str80   label   = ""
    gen str2045 include = ""
    gen str2045 exclude = ""

    * ---------------- analgesics / CNS
    local OPI   "CODEINE|DIHYDROCODEINE|FENTANYL|HYDROCODONE|HYDROMORPHONE|LEVORPHANOL|MEPERIDINE|METHADONE|MORPHINE|OPIUM|OXYCODONE|OXYMORPHONE|PENTAZOCINE|TAPENTADOL|TRAMADOL|BUTORPHANOL|BUPRENORPHINE|BENZHYDROCODONE"
    local BUPMG "BUPRENORPHINE.*[|] [0-9.]+ ?MG|SUBOXONE|SUBUTEX|ZUBSOLV|BUNAVAIL|SUBLOCADE|BRIXADI"
    local NSN   "DICLOFENAC|DIFLUNISAL|ETODOLAC|FENOPROFEN|FLURBIPROFEN|IBUPROFEN|INDOMETHACIN|KETOPROFEN|KETOROLAC|MECLOFENAMATE|MEFENAMIC|MELOXICAM|NABUMETONE|NAPROXEN|OXAPROZIN|PIROXICAM|SALSALATE|SULINDAC|TOLMETIN"
    local TOPX  "%|OPHTHALMIC|TOPICAL|TRANSDERM"
    local SSRI  "CITALOPRAM|FLUOXETINE|FLUVOXAMINE|PAROXETINE|SERTRALINE|VILAZODONE|VORTIOXETINE"
    local SNRI  "DULOXETINE|VENLAFAXINE|LEVOMILNACIPRAN|MILNACIPRAN"
    local TCA   "AMITRIPTYLINE|AMOXAPINE|CLOMIPRAMINE|DESIPRAMINE|DOXEPIN|IMIPRAMINE|MAPROTILINE|NORTRIPTYLINE|PROTRIPTYLINE|TRIMIPRAMINE"

    _pdm_add opioid        "Opioid analgesics (excl. buprenorphine MOUD products)" "`OPI'" "APOMORPHINE|`BUPMG'"
    _pdm_add opioid_moud   "Buprenorphine for OUD (mg-dosed SL/injectable)" "`BUPMG'" ""
    _pdm_add nsaid         "NSAIDs, systemic (non-selective + COX-2)" "`NSN'|CELECOXIB" "`TOPX'"
    _pdm_add nsaid_nonsel  "NSAIDs, systemic non-selective" "`NSN'" "`TOPX'"
    _pdm_add nsaid_cox2    "COX-2 selective NSAID (celecoxib)" "CELECOXIB" "`TOPX'"
    _pdm_add nsaid_topical "NSAIDs, topical / ophthalmic" "(`NSN'|BROMFENAC|NEPAFENAC).*(`TOPX')" ""
    _pdm_add gabapentinoid "Gabapentinoids" "GABAPENTIN|PREGABALIN" ""
    _pdm_add muscle_relax  "Skeletal muscle relaxants" "BACLOFEN|CARISOPRODOL|CHLORZOXAZONE|CYCLOBENZAPRINE|DANTROLENE|METAXALONE|METHOCARBAMOL|ORPHENADRINE|TIZANIDINE" ""
    _pdm_add benzo         "Benzodiazepines" "ALPRAZOLAM|CHLORDIAZEPOXIDE|CLOBAZAM|CLONAZEPAM|CLORAZEPATE|DIAZEPAM|ESTAZOLAM|FLURAZEPAM|LORAZEPAM|MIDAZOLAM|OXAZEPAM|QUAZEPAM|TEMAZEPAM|TRIAZOLAM" ""
    _pdm_add zdrug         "Z-drug hypnotics" "ZOLPIDEM|ZALEPLON|ESZOPICLONE" ""
    _pdm_add antidep       "Antidepressants, any" "`SSRI'|`SNRI'|`TCA'|BUPROPION|MIRTAZAPINE|TRAZODONE|NEFAZODONE|PHENELZINE|TRANYLCYPROMINE|ISOCARBOXAZID" "%"
    _pdm_add antidep_ssri  "SSRIs" "`SSRI'" ""
    _pdm_add antidep_snri  "SNRIs" "`SNRI'" ""
    _pdm_add antidep_tca   "Tricyclic antidepressants" "`TCA'" "%"
    _pdm_add antipsych     "Antipsychotics" "ARIPIPRAZOLE|ASENAPINE|BREXPIPRAZOLE|CARIPRAZINE|CHLORPROMAZINE|CLOZAPINE|FLUPHENAZINE|HALOPERIDOL|ILOPERIDONE|LOXAPINE|LUMATEPERONE|LURASIDONE|OLANZAPINE|PALIPERIDONE|PERPHENAZINE|PIMAVANSERIN|QUETIAPINE|RISPERIDONE|THIORIDAZINE|THIOTHIXENE|TRIFLUOPERAZINE|ZIPRASIDONE" ""
    local CEX "%|MCG|/ACT|ACTUAT|/INH|/SPR|MG/2 ?ML|MG/G|FORMOTEROL|SALMETEROL|VILANTEROL|FLUDROCORTISONE|NEOMYCIN|POLYMYXIN|TOBRAMYCIN|CIPROFLOXACIN|PRAMOXINE|LIDOCAINE|NYSTATIN|CLOTRIMAZOLE|OPHTHALMIC|OTIC|TOPICAL|RECTAL|NASAL|INHAL"
    _pdm_add cortico_sys   "Corticosteroids, systemic (oral/injectable)" "PREDNISONE|PREDNISOLONE|METHYLPREDNISOLONE|DEXAMETHASONE|HYDROCORTISONE|CORTISONE|BETAMETHASONE|TRIAMCINOLONE|BUDESONIDE|DEFLAZACORT" "`CEX'"
    _pdm_add cortico_core  "Prednisone, prednisolone, methylprednisolone, dexamethasone (systemic)" "PREDNISONE|PREDNISOLONE|DEXAMETHASONE|RAYOS|ORAPRED|MEDROL|DECADRON" "`CEX'"
    _pdm_add ppi           "Proton pump inhibitors" "OMEPRAZOLE|ESOMEPRAZOLE|LANSOPRAZOLE|DEXLANSOPRAZOLE|PANTOPRAZOLE|RABEPRAZOLE" ""
    _pdm_add smoking_cess  "Smoking cessation (varenicline, Rx nicotine)" "VARENICLINE|NICOTINE" ""

    * ---------------- bone / hormones
    _pdm_add bisphos_oral   "Bisphosphonates, oral" "ALENDRONATE|RISEDRONATE|IBANDRONATE|ETIDRONATE|TILUDRONATE" "3 ?MG/3 ?ML"
    _pdm_add bisphos_iv     "Bisphosphonates, IV (mostly Part B)" "ZOLEDRONIC|PAMIDRONATE|IBANDRONATE.*3 ?MG/3 ?ML" ""
    _pdm_add denosumab      "Denosumab (mostly Part B)" "DENOSUMAB" ""
    _pdm_add osteo_anabolic "Osteoanabolics (teriparatide, abaloparatide, romosozumab)" "TERIPARATIDE|ABALOPARATIDE|ROMOSOZUMAB" ""
    _pdm_add serm           "SERMs for osteoporosis (raloxifene, bazedoxifene)" "RALOXIFENE|BAZEDOXIFENE" ""
    _pdm_add estrogen       "Estrogens, any route" "ESTRADIOL|ESTROGENS|ESTROPIPATE" ""
    _pdm_add estrogen_sys   "Estrogens excl. vaginal products" "ESTRADIOL|ESTROGENS|ESTROPIPATE" "VAGIN|VAGIFEM|YUVAFEM|IMVEXXY|ESTRING|MG/G|[|] (4|10|25) ?MCG"
    _pdm_add aromatase_inh  "Aromatase inhibitors" "ANASTROZOLE|LETROZOLE|EXEMESTANE" ""

    * ---------------- DMARDs (inflammatory arthritis protocol lists)
    * Infliximab, rituximab, IV abatacept/tocilizumab/golimumab are mostly
    * Part B infusions and are under-ascertained in PDE.
    local CSD "METHOTREXATE|LEFLUNOMIDE|HYDROXYCHLOROQUINE|SULFASALAZINE|TREXALL|OTREXUP|RASUVO|ARAVA|PLAQUENIL|AZULFIDINE"
    local TNF "ADALIMUMAB|ETANERCEPT|INFLIXIMAB|CERTOLIZUMAB|GOLIMUMAB|HUMIRA|ENBREL|REMICADE|CIMZIA|SIMPONI"
    local ILX "TOCILIZUMAB|SARILUMAB|ANAKINRA|SECUKINUMAB|IXEKIZUMAB|USTEKINUMAB|GUSELKUMAB|ACTEMRA|KEVZARA|KINERET|COSENTYX|TALTZ|STELARA|TREMFYA"
    local BIO "`TNF'|ABATACEPT|RITUXIMAB|ORENCIA|RITUXAN|`ILX'"
    local TSD "TOFACITINIB|BARICITINIB|UPADACITINIB|XELJANZ|OLUMIANT|RINVOQ"
    _pdm_add dmard_cs   "Conventional synthetic DMARDs (MTX, leflunomide, HCQ, SSZ)" "`CSD'" ""
    _pdm_add dmard_bio  "Biologic DMARDs (TNFi, abatacept, rituximab, IL inhibitors)" "`BIO'" ""
    _pdm_add dmard_tnf  "TNF inhibitors" "`TNF'" ""
    _pdm_add dmard_il   "IL-1/6/17/12-23/23 inhibitors" "`ILX'" ""
    _pdm_add dmard_ts   "Targeted synthetic DMARDs (JAK inhibitors)" "`TSD'" ""
    _pdm_add dmard_bts  "Biologic or targeted synthetic DMARDs" "`BIO'|`TSD'" ""
    _pdm_add dmard_any  "Any DMARD (cs, b, ts)" "`CSD'|`BIO'|`TSD'" ""

    * ---------------- diabetes
    local GLP "SEMAGLUTIDE|LIRAGLUTIDE|DULAGLUTIDE|EXENATIDE|LIXISENATIDE|ALBIGLUTIDE|TIRZEPATIDE"
    local SU  "GLIPIZIDE|GLYBURIDE|GLIMEPIRIDE|CHLORPROPAMIDE|TOLBUTAMIDE|TOLAZAMIDE"
    local SG  "CANAGLIFLOZIN|DAPAGLIFLOZIN|EMPAGLIFLOZIN|ERTUGLIFLOZIN|BEXAGLIFLOZIN|SOTAGLIFLOZIN"
    local DP  "SITAGLIPTIN|SAXAGLIPTIN|LINAGLIPTIN|ALOGLIPTIN"
    local TZ  "PIOGLITAZONE|ROSIGLITAZONE"
    _pdm_add glp1ra       "GLP-1 receptor agonists (incl. tirzepatide)" "`GLP'" ""
    _pdm_add insulin      "Insulins" "INSULIN" ""
    _pdm_add metformin    "Metformin (incl. combinations)" "METFORMIN" ""
    _pdm_add sulfonylurea "Sulfonylureas" "`SU'" ""
    _pdm_add sglt2        "SGLT2 inhibitors" "`SG'" ""
    _pdm_add dpp4         "DPP-4 inhibitors" "`DP'" ""
    _pdm_add tzd          "Thiazolidinediones" "`TZ'" ""
    _pdm_add antidiab     "Any glucose-lowering drug" "`GLP'|INSULIN|METFORMIN|`SU'|`SG'|`DP'|`TZ'|REPAGLINIDE|NATEGLINIDE|ACARBOSE|MIGLITOL|PRAMLINTIDE" ""

    * ---------------- cardiovascular / hematologic
    local DOAC "APIXABAN|RIVAROXABAN|DABIGATRAN|EDOXABAN|BETRIXABAN"
    local INJ  "ENOXAPARIN|DALTEPARIN|TINZAPARIN|FONDAPARINUX|DESIRUDIN|DANAPAROID|BIVALIRUDIN|ARGATROBAN|HEPARIN"
    _pdm_add anticoag     "Anticoagulants, any" "`DOAC'|WARFARIN|`INJ'" "FLUSH|LOCK"
    _pdm_add doac         "Direct oral anticoagulants" "`DOAC'" ""
    _pdm_add warfarin     "Warfarin" "WARFARIN" ""
    _pdm_add anticoag_inj "Injectable anticoagulants (LMWH, fondaparinux, ...)" "`INJ'" "FLUSH|LOCK"
    _pdm_add antiplatelet "P2Y12 / other antiplatelets (aspirin is OTC, not captured)" "CLOPIDOGREL|PRASUGREL|TICAGRELOR|TICLOPIDINE|DIPYRIDAMOLE|CILOSTAZOL|VORAPAXAR" ""
    _pdm_add statin       "Statins" "ATORVASTATIN|ROSUVASTATIN|SIMVASTATIN|PRAVASTATIN|LOVASTATIN|FLUVASTATIN|PITAVASTATIN" ""
    _pdm_add acei         "ACE inhibitors" "BENAZEPRIL|CAPTOPRIL|ENALAPRIL|FOSINOPRIL|LISINOPRIL|MOEXIPRIL|PERINDOPRIL|QUINAPRIL|RAMIPRIL|TRANDOLAPRIL" ""
    _pdm_add arb          "Angiotensin receptor blockers (incl. sacubitril/valsartan)" "AZILSARTAN|CANDESARTAN|EPROSARTAN|IRBESARTAN|LOSARTAN|OLMESARTAN|TELMISARTAN|VALSARTAN" ""
    _pdm_add betablocker  "Beta blockers, systemic" "ACEBUTOLOL|ATENOLOL|BETAXOLOL|BISOPROLOL|CARVEDILOL|LABETALOL|METOPROLOL|NADOLOL|NEBIVOLOL|PINDOLOL|PROPRANOLOL|SOTALOL|TIMOLOL" "%|OPHTHALMIC"
    _pdm_add ccb          "Calcium channel blockers" "AMLODIPINE|LEVAMLODIPINE|DILTIAZEM|FELODIPINE|ISRADIPINE|NICARDIPINE|NIFEDIPINE|NIMODIPINE|NISOLDIPINE|VERAPAMIL" "%"
    _pdm_add loop_diur    "Loop diuretics" "FUROSEMIDE|BUMETANIDE|TORSEMIDE|ETHACRYNIC" ""
    _pdm_add thiazide     "Thiazide / thiazide-like diuretics" "HYDROCHLOROTHIAZIDE|CHLOROTHIAZIDE|CHLORTHALIDONE|INDAPAMIDE|METOLAZONE" ""
end
