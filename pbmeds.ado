*! pbmeds 1.0.0  16nov2026
*! Physician-/facility-administered drug exposure from provider procedure 
*! claims files (e.g. Medicare Part B carrier line) and outpatient revenue-center 
*! claims, by HCPCS code, in windows around an index date. Companion to pdemeds (same windows, class
*! names, and an option to combine with pdemeds results).
*!
*!   pbmeds, files(LINEB16 LINEB17 OPREV16 OPREV17) id(link) index(indexadm) ///
*!           classes(dmard_bio dmard_tnf cortico_inj) windows(pre:-180/-1 post:0/90) ///
*!           stats(any n first) combine(rx_)
*!
*! Creates <prefix><class>_<window>_<stat> (default prefix pb_).
*! n = number of distinct administration DAYS (lines on the same day count once).

program define pbmeds, rclass
    version 16
    syntax [, FILEs(string asis) ID(varname) INDEX(varname numeric)          ///
        PERSON(name) CLASSes(string) DEFfile(string) WINdows(string)        ///
        STATs(string) PREfix(string) ENROLLed(varname numeric)              ///
        HCPCS(name) DATEvars(string) UNITvars(string)                       ///
        COMBine(string) PDPrefix(string) SAVEclaims(string)                 ///
        LISTclasses EXPORTclasses(string) REPLACE NOREPort ]

    *--------------------------------------------------------------------*
    * utility modes
    *--------------------------------------------------------------------*
    if "`listclasses'" != "" | `"`exportclasses'"' != "" {
        preserve
        quietly _pbmeds_lib
        if `"`deffile'"' != "" quietly _pbmeds_deffile `"`deffile'"'
        if "`listclasses'" != "" {
            di as txt _n "{hline 78}"
            forvalues k = 1/`=_N' {
                di as res %-16s class[`k'] as txt "  " label[`k']
                di as txt _col(19) include[`k']
            }
            di as txt "{hline 78}"
        }
        if `"`exportclasses'"' != "" {
            export delimited class label include using `"`exportclasses'"', replace quote
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
    if "`hcpcs'"    == "" local hcpcs    hcpcs_cd
    if "`datevars'" == "" local datevars line_1st_expns_dt rev_cntr_dt clm_thru_dt
    if "`unitvars'" == "" local unitvars line_srvc_cnt rev_cntr_unit_cnt
    if "`prefix'"   == "" local prefix   pb_
    if "`prefix'"   == "none" local prefix
    if `"`windows'"' == "" local windows "pre:-90/-1 post:0/90"
    if "`stats'"    == "" local stats    "any n"
    local stats = lower("`stats'")
    local stats : list uniq stats
    local okstats any n first last units
    foreach s of local stats {
        if !`: list s in okstats' {
            di as err "stats(): `s' not allowed. Choose from: `okstats'"
            exit 198
        }
    }
    local want_units = `: list posof "units" in stats' > 0

    * ---- windows  name:lo/hi
    local wnames
    local lomin .
    local himax .
    foreach w of local windows {
        if !ustrregexm(`"`w'"', "^([A-Za-z][A-Za-z0-9_]*):(-?[0-9]+)/(-?[0-9]+)") {
            di as err `"windows(): "`w'" is not of the form name:lo/hi"'
            exit 198
        }
        local nm = ustrregexs(1)
        local lo = ustrregexs(2)
        local hi = ustrregexs(3)
        if `lo' > `hi' {
            di as err "windows(): `nm' has lo > hi"
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
        _pbmeds_lib
        if `"`deffile'"' != "" _pbmeds_deffile `"`deffile'"'
        if !inlist(lower("`classes'"), "", "all") {
            gen byte _sel = 0
            foreach c of local classes {
                count if class == "`c'"
                if r(N) == 0 {
                    noisily di as err "class `c' is not defined for Part B (see: pbmeds, listclasses)"
                    exit 111
                }
                replace _sel = 1 if class == "`c'"
            }
            keep if _sel
        }
        local K = _N
        local allcls
        local allrx
        forvalues k = 1/`K' {
            local cls`k' = class[`k']
            local lab`k' = label[`k']
            local inc`k' = include[`k']
            local allcls `allcls' `cls`k''
            if `k' == 1 local allrx (`inc`k'')
            else        local allrx `allrx'|(`inc`k'')
        }
    }
    restore

    * ---- output names
    local outvars
    local combvars
    forvalues k = 1/`K' {
        foreach w of local wnames {
            foreach s of local stats {
                local v `prefix'`cls`k''_`w'_`s'
                if strlen("`v'") > 32 {
                    di as err "variable name `v' exceeds 32 characters"
                    exit 198
                }
                local outvars `outvars' `v'
                if "`combine'" != "" & "`s'" != "units" {
                    local cv `combine'`cls`k''_`w'_`s'
                    if strlen("`cv'") > 32 {
                        di as err "variable name `cv' exceeds 32 characters"
                        exit 198
                    }
                    local combvars `combvars' `cv'
                }
            }
        }
    }

    *--------------------------------------------------------------------*
    * cohort keys
    *--------------------------------------------------------------------*
    preserve
    confirm variable `person'
    capture isid `id'
    if _rc {
        di as err "id(`id') does not uniquely identify observations"
        exit 459
    }
    foreach v in `outvars' `combvars' {
        capture confirm new variable `v'
        if _rc {
            if "`replace'" != "" drop `v'
            else {
                di as err "variable `v' already exists; specify replace"
                exit 110
            }
        }
    }
    tempfile cohort keys lines res
    quietly save `cohort'
    local kv `id' `person' `index'
    local kv : list uniq kv
    quietly {
        keep `kv'
        drop if missing(`index')
        rename `index' _pdm_index
        save `keys'
    }

    *--------------------------------------------------------------------*
    * read each claim file once; keep only class HCPCS lines of cohort members
    *--------------------------------------------------------------------*
    local have 0
    local nfiles 0
    foreach f of local files {
        local ++nfiles
        quietly describe using `"`f'"', varlist
        local avail `r(varlist)'
        local fp
        local fh
        local fd
        local fu
        foreach a of local avail {
            if lower("`a'") == lower("`person'") local fp `a'
            if lower("`a'") == lower("`hcpcs'")  local fh `a'
        }
        foreach d of local datevars {
            foreach a of local avail {
                if "`fd'" == "" & lower("`a'") == lower("`d'") local fd `a'
            }
        }
        foreach u of local unitvars {
            foreach a of local avail {
                if "`fu'" == "" & lower("`a'") == lower("`u'") local fu `a'
            }
        }
        if "`fp'" == "" | "`fh'" == "" | "`fd'" == "" {
            di as err `"`f': need `person', `hcpcs' and one of (`datevars')"'
            exit 111
        }
        di as txt `"  `f': date = `fd'"' cond("`fu'" != "", ", units = `fu'", "")
        quietly {
            use `fp' `fh' `fd' `fu' if ustrregexm(strtrim(`fh'), "`allrx'") using `"`f'"', clear
            if "`fp'" != "`person'" rename `fp' `person'
            rename (`fh' `fd') (_pb_hcpcs _pb_date)
            if "`fu'" != "" rename `fu' _pb_units
            else gen double _pb_units = .
            gen str244 _pb_file = `"`f'"'
            if _N == 0 continue
            joinby `person' using `keys'
            gen long _pdm_rel = _pb_date - _pdm_index
            keep if inrange(_pdm_rel, `lomin', `himax')
            if _N == 0 continue
            replace _pb_hcpcs = strtrim(_pb_hcpcs)
            forvalues k = 1/`K' {
                gen byte _c`k' = ustrregexm(_pb_hcpcs, `"`inc`k''"')
            }
            if `have' == 0 save `lines'
            else {
                append using `lines'
                save `lines', replace
            }
            local have 1
        }
    }

    *--------------------------------------------------------------------*
    * administration days -> windows -> one row per id
    *--------------------------------------------------------------------*
    local Nlines 0
    if `have' {
        quietly use `lines', clear
        local Nlines = _N
        if "`noreport'" == "" {
            di as txt _n "{hline 60}"
            di as txt "pbmeds: " as res `nfiles' as txt " file(s), " as res `Nlines' as txt " qualifying lines"
            forvalues k = 1/`K' {
                di as txt _n "---- `cls`k''"
                capture noisily tab _pb_hcpcs if _c`k'
            }
            di as txt "{hline 60}"
        }
        if `"`saveclaims'"' != "" {
            quietly {
                forvalues k = 1/`K' {
                    rename _c`k' c_`cls`k''
                }
                rename (_pdm_rel _pb_hcpcs _pb_date _pb_units _pb_file) ///
                       (days_from_index hcpcs date units source_file)
                save `"`saveclaims'"', replace
                use `lines', clear
            }
            di as txt `"line-level file saved: `saveclaims'"'
        }
        quietly {
            forvalues k = 1/`K' {
                gen double _u`k' = _pb_units if _c`k'
            }
            collapse (max) _c* (sum) _u*, by(`id' _pdm_rel)
            local cmax
            local csum
            local cmin
            forvalues k = 1/`K' {
                local j 0
                foreach w of local wnames {
                    local ++j
                    local b `prefix'`cls`k''_`w'
                    gen byte _i`k'_`j' = _c`k' & inrange(_pdm_rel, `wlo_`w'', `whi_`w'')
                    foreach s of local stats {
                        if "`s'" == "any" local cmax `cmax' `b'_any=_i`k'_`j'
                        if "`s'" == "n"   local csum `csum' `b'_n=_i`k'_`j'
                        if inlist("`s'", "first", "last") {
                            capture confirm variable _f`k'_`j'
                            if _rc gen long _f`k'_`j' = _pdm_rel if _i`k'_`j'
                            if "`s'" == "first" local cmin `cmin' `b'_first=_f`k'_`j'
                            else                local cmax `cmax' `b'_last=_f`k'_`j'
                        }
                        if "`s'" == "units" {
                            gen double _v`k'_`j' = _u`k' if _i`k'_`j'
                            local csum `csum' `b'_units=_v`k'_`j'
                        }
                    }
                }
            }
            local cmd
            if "`cmax'" != "" local cmd `cmd' (max) `cmax'
            if "`csum'" != "" local cmd `cmd' (sum) `csum'
            if "`cmin'" != "" local cmd `cmd' (min) `cmin'
            collapse `cmd', by(`id')
            save `res'
        }
    }
    else di as txt "pbmeds: no qualifying lines found for the cohort"

    *--------------------------------------------------------------------*
    * assemble + optional combination with pdemeds results
    *--------------------------------------------------------------------*
    quietly {
        use `cohort', clear
        if `have' merge 1:1 `id' using `res', keep(master match) nogen
        capture label define _pdm_yn 0 "no" 1 "yes"
        local sdesc_any   "any administration"
        local sdesc_n     "no. of administration days"
        local sdesc_first "first administration, days from index"
        local sdesc_last  "last administration, days from index"
        local sdesc_units "HCPCS units billed"
        local nocomb
        forvalues k = 1/`K' {
            foreach w of local wnames {
                local b `prefix'`cls`k''_`w'
                foreach s of local stats {
                    local v `b'_`s'
                    capture confirm variable `v'
                    if _rc {
                        if inlist("`s'", "first", "last") gen long `v' = .
                        else gen double `v' = 0
                    }
                    if inlist("`s'", "any", "n", "units") replace `v' = 0 if missing(`v')
                    replace `v' = . if missing(`index')
                    if "`enrolled'" != "" replace `v' = . if `enrolled' != 1
                    if inlist("`s'", "any", "n") compress `v'
                    if "`s'" == "any" label values `v' _pdm_yn
                    local L = substr(`"`lab`k'' (Part B) [`w' `wlo_`w''..`whi_`w'']: `sdesc_`s''"', 1, 80)
                    label variable `v' `"`L'"'

                    * combine with pdemeds variable of the same class/window/stat
                    if "`combine'" == "" | "`s'" == "units" continue
                    local pd `pdprefix'`cls`k''_`w'_`s'
                    local cv `combine'`cls`k''_`w'_`s'
                    capture confirm variable `pd'
                    if _rc {
                        local nocomb `nocomb' `pd'
                        continue
                    }
                    if "`s'" == "any"   gen byte   `cv' = max(`v', `pd')
                    if "`s'" == "n"     egen double `cv' = rowtotal(`v' `pd'), missing
                    if "`s'" == "first" gen long   `cv' = min(`v', `pd')
                    if "`s'" == "last"  gen long   `cv' = max(`v', `pd')
                    if "`s'" == "any"   label values `cv' _pdm_yn
                    local stxt = cond("`s'" == "n", "PDE fills + Part B days", "`sdesc_`s''")
                    local L = substr(`"`lab`k'' (PDE+B) [`w']: `stxt'"', 1, 80)
                    label variable `cv' `"`L'"'
                }
            }
        }
    }
    restore, not

    if "`nocomb'" != "" {
        di as txt "note: no pdemeds counterpart (run pdemeds first with the same classes/windows):"
        di as txt "      `nocomb'"
    }
    di as txt "pbmeds: created " as res `: word count `outvars'' as txt " Part B variables" ///
        cond("`combine'" != "", " plus combined PDE+B variables (prefix `combine')", "")
    return local varlist "`outvars'"
    return local classes "`allcls'"
    return local windows `"`windows'"'
    return scalar N_lines = `Nlines'
end


*==========================================================================*
* user definitions (CSV: class,label,include) replace/extend library
*==========================================================================*
program define _pbmeds_deffile
    args fn
    tempfile lib usr
    save `lib'
    import delimited using `"`fn'"', clear varnames(1) case(lower) ///
        stringcols(_all) bindquote(strict)
    confirm variable class include
    capture confirm variable label
    if _rc gen label = ""
    keep class label include
    replace class = strtrim(class)
    drop if class == ""
    isid class
    save `usr'
    use `lib', clear
    merge 1:1 class using `usr', keep(master) nogen
    append using `usr'
end

program define _pbm_add
    args class label codes
    local N = _N + 1
    set obs `N'
    replace class   = `"`class'"' in `N'
    replace label   = `"`label'"' in `N'
    replace include = "^(" + `"`codes'"' + ")" in `N'
end

*--------------------------------------------------------------------------*
* Built-in Part B HCPCS library. Class names match pdemeds so that
* combine() works. Verify against the CMS HCPCS file for your years:
* codes are added/deleted over time (both old and new codes are listed).
*--------------------------------------------------------------------------*
program define _pbmeds_lib
    clear
    gen str16   class   = ""
    gen str80   label   = ""
    gen str2045 include = ""

    * ---- DMARDs
    * methotrexate: J8610 oral, J9250/J9260/J9255 injection (also oncology!)
    local MTX "J8610|J9250|J9260|J9255"
    * TNF inhibitors: infliximab J1745 + biosimilars Q5102 (to 3/2018),
    * Q5103 Inflectra, Q5104 Renflexis, Q5109 Ixifi, Q5121 Avsola;
    * adalimumab J0135, etanercept J1438, certolizumab J0717, golimumab IV J1602
    local TNF "J1745|Q5102|Q5103|Q5104|Q5109|Q5121|J0135|J1438|J0717|J1602"
    * IL inhibitors: tocilizumab J3262, ustekinumab J3357 (SC) / J3358 (IV),
    * guselkumab J1628. (Secukinumab, ixekizumab, sarilumab, anakinra have no
    * specific Part B code in 2016-2021; they appear in PDE.)
    local ILX "J3262|J3357|J3358|J1628"
    * rituximab J9310 (to 2018), J9312 (2019+), J9311 Rituxan Hycela,
    * biosimilars Q5115 Truxima, Q5119 Ruxience, Q5123 Riabni (mostly oncology!)
    local RTX "J9310|J9311|J9312|Q5115|Q5119|Q5123"
    local ABA "J0129"
    local BIO "`TNF'|`ABA'|`RTX'|`ILX'"
    _pbm_add dmard_cs  "Methotrexate (Part B oral/injection)" "`MTX'"
    _pbm_add dmard_bio "Biologic DMARDs (Part B)" "`BIO'"
    _pbm_add dmard_tnf "TNF inhibitors (Part B)" "`TNF'"
    _pbm_add dmard_il  "IL-6/12-23/23 inhibitors (Part B)" "`ILX'"
    _pbm_add dmard_rtx "Rituximab incl. biosimilars (Part B)" "`RTX'"
    _pbm_add dmard_bts "Biologic DMARDs (Part B; JAKi are oral/PDE only)" "`BIO'"
    _pbm_add dmard_any "Any DMARD (Part B)" "`MTX'|`BIO'"

    * ---- corticosteroids
    * core four (protocol): methylprednisolone acetate J1020/J1030/J1040
    * (J1010 from 4/2024), sodium succinate J2920/J2930, oral J7509;
    * dexamethasone J1100, J1094, oral J8540; prednisone oral J7506/J7512;
    * prednisolone oral J7510
    local CORE "J1010|J1020|J1030|J1040|J2920|J2930|J7509|J1100|J1094|J8540|J7506|J7512|J7510"
    * all injectable corticosteroids incl. epidural/joint injections:
    * + betamethasone J0702, triamcinolone J3300-J3303, hydrocortisone J1700-J1720
    local INJ "J0702|J1010|J1020|J1030|J1040|J1094|J1100|J2920|J2930|J3300|J3301|J3302|J3303|J1700|J1710|J1720"
    _pbm_add cortico_core "Pred/prednisolone/methylpred/dex (Part B)" "`CORE'"
    _pbm_add cortico_inj  "Injectable corticosteroids incl. epidural/joint (Part B)" "`INJ'"

    * ---- spinal injection PROCEDURES (CPT; on the physician carrier claim in
    * every setting). Epidural steroid injections: interlaminar 62310/62311
    * (to 2016) -> 62320-62323 (2017+); transforaminal 64479/64480/64483/64484.
    * Catheter/infusion codes 62318/62319/62324-62327 are excluded (mostly
    * labor or post-op analgesia). CPT does not say which substance was used.
    _pbm_add esi       "Epidural steroid injection (interlaminar/transforaminal)" "62310|62311|62320|62321|62322|62323|64479|64480|64483|64484"
    _pbm_add facet_sij "Facet joint / SI joint injection" "64490|64491|64492|64493|64494|64495|27096|G0260"

    * ---- bone
    _pbm_add bisphos_iv     "IV bisphosphonates: zoledronic J3489, ibandronate J1740, pamidronate J2430" "J3489|J1740|J2430"
    _pbm_add denosumab      "Denosumab J0897" "J0897"
    _pbm_add osteo_anabolic "Teriparatide J3110, romosozumab J3111" "J3110|J3111"
end
