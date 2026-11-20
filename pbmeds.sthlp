{smcl}
{* *! version 1.0.0  20nov2026}{...}
{title:Title}

{phang}
{bf:pbmeds} {hline 2} Provider-administered drugs and procedures (HCPCS/CPT) from medical claims in windows around an index date


{title:Syntax}

{p 8 16 2}
{cmd:pbmeds} {cmd:,} {opt files(filelist)} {opt id(varname)} {opt index(varname)} [{it:options}]

{p 8 16 2}
{cmd:pbmeds} {cmd:,} {opt listclasses} | {opt exportclasses(filename.csv)} [{opt deffile(filename.csv)}]

{synoptset 26 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Required}
{synopt:{opt files(filelist)}}medical claim line .dta files, e.g. {cmd:files(med2019 med2020 "my dir/hospout2020")}{p_end}
{synopt:{opt id(varname)}}cohort unit (one row per id), e.g. a person or episode id{p_end}
{synopt:{opt index(varname)}}daily date the windows are anchored on{p_end}

{syntab:What to measure}
{synopt:{opt classes(list)}}classes from the library (default {cmd:all}){p_end}
{synopt:{opt windows(list)}}{it:name}{cmd::}{it:lo}{cmd:/}{it:hi} days relative to index, inclusive (default {cmd:pre:-90/-1 post:0/90}){p_end}
{synopt:{opt stats(list)}}any n first last units (default {cmd:any n}){p_end}
{synopt:{opt deffile(csv)}}your own HCPCS/CPT classes; replace or extend the library{p_end}
{synopt:{opt prefix(str)}}prefix for created variables (default {cmd:pb_}; {cmd:prefix(none)} for no prefix){p_end}
{synopt:{opt enrolled(varname)}}set results to missing unless {it:varname}==1 (e.g. continuous medical coverage over the window){p_end}
{synopt:{opt replace}}overwrite existing result variables{p_end}

{syntab:Combine with pdemeds}
{synopt:{opt combine(prefix)}}also create pharmacy + medical-claims variables with this prefix{p_end}
{synopt:{opt pdprefix(str)}}prefix used when {cmd:pdemeds} was run (default none){p_end}

{syntab:Claim variable names (defaults are CMS CCW Medicare names; matched case-insensitively)}
{synopt:{opt person(bene_id)}}person key shared by the cohort and the claim files{p_end}
{synopt:{opt hcpcs(hcpcs_cd)}}HCPCS/CPT procedure code{p_end}
{synopt:{opt datevars(list)}}candidate service-date variables; the first one found in each file is used
(default {cmd:line_1st_expns_dt rev_cntr_dt clm_thru_dt}){p_end}
{synopt:{opt unitvars(list)}}candidate unit variables (default {cmd:line_srvc_cnt rev_cntr_unit_cnt}){p_end}

{syntab:Output / audit}
{synopt:{opt saveclaims(file)}}save the qualifying line-level file (always replaces){p_end}
{synopt:{opt noreport}}suppress the per-class code tabulations{p_end}
{synoptline}


{title:Description}

{pstd}
{cmd:pbmeds} takes a cohort in memory: one row per {it:id}, with a person key and an index date.
It reads each claim file once, keeping only lines whose HCPCS/CPT code belongs to a selected class
(filtered while loading, so large line files stay manageable).
It then restricts to cohort members inside the widest window and collapses to one row per {it:id}.
Each class x window x statistic becomes a variable {it:prefix}{it:class}{cmd:_}{it:window}{cmd:_}{it:stat}.

{pstd}
It is the medical-claims companion to {help pdemeds}: same windows, and the same class names wherever a class exists in both.
That way {opt combine()} can produce exposure measures that use both pharmacy and medical claims.
That matters for drugs that are usually given in a clinic or infusion center rather than dispensed by a pharmacy
(infliximab, rituximab, IV bisphosphonates, denosumab, injectable steroids).


{title:Data requirements and other data sources}

{pstd}
{cmd:pbmeds} works with any line-level medical claims or encounter data coded with US HCPCS Level II and CPT codes,
with a person key, a service date and the code (units are optional).
Examples are Medicare carrier and outpatient files, commercial outpatient service tables, Medicaid outpatient claims,
and EHR procedure or medication-administration records that carry HCPCS/CPT codes.

{pstd}
The defaults are the CMS CCW Medicare names. For other sources set {opt person()} and {opt hcpcs()}, and list your
service-date and unit variables in {opt datevars()} and {opt unitvars()}. Files can differ: for each file, the first
listed date (and unit) variable present is used, so professional and facility files with different names can be
read in one call.

{pstd}
{bf:Include both professional and facility claims.} A drug given in a physician office is billed on the
professional claim. A drug given in a hospital outpatient department or infusion center is usually billed on the
{it:facility} claim (in Medicare, the outpatient revenue-center file). List both, or hospital-based infusions will be missed.
Procedures such as epidural steroid injections appear on the professional claim in every setting.

{pstd}
{bf:Code fields.} If your procedure-code field mixes code systems (CPT/HCPCS with ICD procedure or revenue codes),
keep only HCPCS/CPT rows first. Drugs billed under unclassified codes (e.g. J3490, J3590) are identified only by an
NDC on the claim and are not captured by the built-in classes.


{title:Statistics}

{p2colset 9 20 22 2}{...}
{p2col:{cmd:any}}any qualifying line with service date in window (0/1){p_end}
{p2col:{cmd:n}}number of distinct administration/procedure {it:days} (several lines on one day count once){p_end}
{p2col:{cmd:first}/{cmd:last}}day (relative to index) of the first / last administration in window{p_end}
{p2col:{cmd:units}}sum of HCPCS units billed (dose units for J-codes, e.g. 10 mg for infliximab){p_end}
{p2colreset}{...}

{pstd}
With {opt combine()}: {cmd:any} = either source; {cmd:n} = pharmacy fills + administration days; {cmd:first} = earliest; {cmd:last} = latest.
{cmd:pdemeds} must have been run first with the same class and window names.


{title:Class library}

{pstd}
{cmd:pbmeds, listclasses} shows each class with its codes.

{p2colset 9 26 28 2}{...}
{p2col:{cmd:dmard_cs}}methotrexate J8610, J9250, J9260, J9255 (also used in oncology){p_end}
{p2col:{cmd:dmard_tnf}}infliximab J1745 and biosimilars Q5102-Q5104, Q5109, Q5121; adalimumab J0135; etanercept J1438; certolizumab J0717; golimumab IV J1602{p_end}
{p2col:{cmd:dmard_il}}tocilizumab J3262; ustekinumab J3357 (SC), J3358 (IV); guselkumab J1628{p_end}
{p2col:{cmd:dmard_rtx}}rituximab J9310 (to 2018), J9312, J9311 and biosimilars Q5115, Q5119, Q5123 (often oncology use){p_end}
{p2col:{cmd:dmard_bio}}TNF + IL + rituximab + abatacept J0129{p_end}
{p2col:{cmd:dmard_bts}}same as dmard_bio (JAK inhibitors are oral and appear in pharmacy claims){p_end}
{p2col:{cmd:dmard_any}}dmard_cs + dmard_bio{p_end}
{p2col:{cmd:cortico_core}}methylprednisolone, dexamethasone, prednisone, prednisolone (injectable and oral HCPCS codes){p_end}
{p2col:{cmd:cortico_inj}}all injectable corticosteroids, incl. betamethasone and triamcinolone (any injection site){p_end}
{p2col:{cmd:esi}}epidural steroid injection procedures: 62310/62311 (to 2016), 62320-62323 (2017+), transforaminal 64479/64480/64483/64484; catheter codes excluded{p_end}
{p2col:{cmd:facet_sij}}facet joint injections 64490-64495, SI joint injection 27096, G0260{p_end}
{p2col:{cmd:bisphos_iv}}zoledronic acid J3489, ibandronate J1740, pamidronate J2430{p_end}
{p2col:{cmd:denosumab}}J0897{p_end}
{p2col:{cmd:osteo_anabolic}}teriparatide J3110, romosozumab J3111{p_end}
{p2colreset}{...}

{pstd}
Secukinumab, ixekizumab, sarilumab, anakinra, the JAK inhibitors and the oral conventional DMARDs had no specific
HCPCS code in 2016-2021 and are mostly dispensed by pharmacies. Use {help pdemeds} for these.

{pstd}
{bf:Codes change over time.} The library lists 2016-2021 codes, including retired codes and their replacements.
For other years, check the current HCPCS and CPT code sets and add codes via {opt deffile()}.
Export the library, edit the CSV (columns class, label, include), and pass it back.
{it:include} is a regular expression matched against the trimmed code, e.g. {cmd:^(J1745|Q5103)}.

{phang2}{cmd:. pbmeds, exportclasses(pbclasses.csv)}{p_end}


{title:Examples}

{pstd}Medicare carrier and outpatient revenue-center files (default variable names){p_end}

{phang2}{cmd:. use studycohort, clear}{p_end}
{phang2}{cmd:. pdemeds, files(PDE16 PDE17 PDE18) id(link) index(indexadm) ///}{p_end}
{phang3}{cmd:classes(dmard_cs dmard_bio dmard_tnf dmard_bts) windows(pre180:-180/-1) stats(any n first)}{p_end}
{phang2}{cmd:. pbmeds, files(LINEB16 LINEB17 LINEB18 OPREV16 OPREV17 OPREV18) id(link) index(indexadm) ///}{p_end}
{phang3}{cmd:classes(dmard_cs dmard_bio dmard_tnf dmard_bts) windows(pre180:-180/-1) stats(any n first) combine(rx_)}{p_end}
{phang2}{cmd:. gen dmardgroup = cond(rx_dmard_bts_pre180_any, 2, rx_dmard_cs_pre180_any)}{p_end}

{pstd}Another data source: professional and facility files with different date and unit names{p_end}

{phang2}{cmd:. pbmeds, files(prof_claims_2020 facility_claims_2020) id(episode_id) person(patient_id) index(surgery_dt) ///}{p_end}
{phang3}{cmd:hcpcs(proc_cd) datevars(svc_from_dt line_svc_dt) unitvars(units svc_units) ///}{p_end}
{phang3}{cmd:classes(esi facet_sij cortico_inj) windows(pre90:-90/-1 pre365:-365/-1) stats(any n last)}{p_end}

{pstd}Audit what was captured{p_end}

{phang2}{cmd:. pbmeds, files(...) id(link) index(indexadm) classes(dmard_bio) saveclaims(pb_audit)}{p_end}
{phang2}{cmd:. use pb_audit, clear}{p_end}
{phang2}{cmd:. tab hcpcs source_file if c_dmard_bio}{p_end}


{title:Notes}

{pstd}
Windows are inclusive, based on service date; day 0 = index date.

{pstd}
Zeros mean "no qualifying claim". That is only interpretable for people whose medical claims are fully captured
in the data source over the window: e.g. continuous enrollment in a plan that submits claims (in Medicare,
fee-for-service rather than Medicare Advantage). Use {opt enrolled()} or restrict the cohort.

{pstd}
Denied or reversed lines are not removed. If your files include them, drop them before running.

{pstd}
Requires Stata 16+.


{title:Installation}

{pstd}
{cmd:pdemeds}, {cmd:pbmeds} and {cmd:pdemme} are installed together as the {cmd:pdemeds} package from GitHub:

{phang2}{cmd:. net install pdemeds, from("https://raw.githubusercontent.com/BrookMartin/pdemeds/main/") replace}{p_end}
{phang2}{cmd:. net get pdemeds, from("https://raw.githubusercontent.com/BrookMartin/pdemeds/main/")}{p_end}

{pstd}
{cmd:net get} downloads the synthetic test suite ({cmd:pdemeds_test.do}) and the class-library CSV templates into the current folder.
Source, documentation and issue tracker: {browse "https://github.com/BrookMartin/pdemeds"}.


{title:Stored results}

{p2colset 9 24 26 2}{...}
{p2col:{cmd:r(varlist)}}variables created (excluding {opt combine()} variables){p_end}
{p2col:{cmd:r(classes)}}classes used{p_end}
{p2col:{cmd:r(windows)}}windows{p_end}
{p2col:{cmd:r(N_lines)}}qualifying lines read{p_end}
{p2colreset}{...}


{title:Also see}

{psee}
{help pdemeds} (pharmacy claims), {help pdemme} (MME per dispensed unit)
{p_end}
