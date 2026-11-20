{smcl}
{* *! version 1.0.0  20nov2026}{...}
{title:Title}

{phang}
{bf:pdemeds} {hline 2} Medication-class exposure from pharmacy dispensing claims in windows around an index date


{title:Syntax}

{p 8 16 2}
{cmd:pdemeds} {cmd:,} {opt files(filelist)} {opt id(varname)} {opt index(varname)} [{it:options}]

{p 8 16 2}
{cmd:pdemeds} {cmd:,} {opt listclasses} | {opt exportclasses(filename.csv)} [{opt deffile(filename.csv)}]

{synoptset 26 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Required}
{synopt:{opt files(filelist)}}pharmacy claim .dta files, e.g. {cmd:files(rx2019 rx2020 "my dir/rx2021.dta")}{p_end}
{synopt:{opt id(varname)}}cohort unit (one row per id), e.g. a person or episode id{p_end}
{synopt:{opt index(varname)}}daily date the windows are anchored on{p_end}

{syntab:What to measure}
{synopt:{opt classes(list)}}classes from the library (default {cmd:all}){p_end}
{synopt:{opt windows(list)}}{it:name}{cmd::}{it:lo}{cmd:/}{it:hi} days relative to index, inclusive (default {cmd:pre:-90/-1 post:0/90}){p_end}
{synopt:{opt stats(list)}}any n days qty first last cov pdc mme mmeday mmemax (default {cmd:any n}){p_end}
{synopt:{opt deffile(csv)}}your own class definitions; replace or extend the library{p_end}
{synopt:{opt prefix(str)}}prefix for created variables{p_end}
{synopt:{opt enrolled(varname)}}set results to missing unless {it:varname}==1 (e.g. continuous pharmacy coverage over the window){p_end}
{synopt:{opt replace}}overwrite existing result variables{p_end}

{syntab:MME}
{synopt:{opt mmecf(cdc2022|cdc2016)}}conversion factors (default {cmd:cdc2022}){p_end}
{synopt:{opt mmeclasses(list)}}classes that get MME statistics (default {cmd:opioid}){p_end}
{synopt:{opt mmefile(file)}}NDC-level crosswalk (.dta or .csv) that overrides the built-in parser{p_end}
{synopt:{opt bupoud(#)}}MME per mg for buprenorphine MOUD products (default: not assigned){p_end}

{syntab:Covered days}
{synopt:{opt carryover(#)}}days before the earliest window searched for fills that carry over (default 180){p_end}

{syntab:Claim variable names (defaults are CMS CCW Part D names; matched case-insensitively)}
{synopt:{opt person(bene_id)}}person key shared by the cohort and the claim files{p_end}
{synopt:{opt srvcdt(srvc_dt)}}dispensing (fill) date{p_end}
{synopt:{opt qty(qty_dspnsd_num)}}quantity dispensed{p_end}
{synopt:{opt days(days_suply_num)}}days supplied{p_end}
{synopt:{opt gnn(gnn)}}generic drug name (text){p_end}
{synopt:{opt bn(bn)}}brand name (text; optional){p_end}
{synopt:{opt strength(str)}}strength (text){p_end}
{synopt:{opt ndc(prod_srvc_id)}}NDC (only needed with {opt mmefile()}){p_end}
{synopt:{opt form(varname)}}optional dosage-form text; improves route exclusions{p_end}

{syntab:Output / audit}
{synopt:{opt saveclaims(file)}}save the flagged claim-level file (always replaces){p_end}
{synopt:{opt noreport}}suppress the summary table{p_end}
{synoptline}


{title:Description}

{pstd}
{cmd:pdemeds} takes a cohort in memory: one row per {it:id}, with a person key and an index date
(a surgery, hospitalization, diagnosis or enrollment date).
It reads each pharmacy claim file once and keeps only cohort members' claims inside the widest window.
It classifies each {it:distinct} drug description (generic name | brand name | strength [| form])
against regular-expression class definitions, then collapses to one row per {it:id}.
Every class x window x statistic becomes a variable {it:prefix}{it:class}{cmd:_}{it:window}{cmd:_}{it:stat}.

{pstd}
Running the regexes on distinct drug descriptions (usually a few thousand) rather than on every
claim (often millions) is what makes this fast on large files.

{pstd}
People with no qualifying fill get 0 (missing for {cmd:first}, {cmd:last}, {cmd:mmemax}).
A 0 means "no claim", which is only interpretable for people who had pharmacy coverage in the data source
over the window. Supply {opt enrolled()} or restrict the cohort.


{title:Data requirements and other data sources}

{pstd}
{cmd:pdemeds} works with any outpatient pharmacy dispensing data that has, per fill:
a person key, a fill date, quantity, days supplied, and the drug's {bf:generic name} and {bf:strength as text}
(brand name and dosage form are optional).
Examples are Medicare Part D event files, commercial claims databases, Medicaid pharmacy claims,
health-system or EHR dispensing records, and registries.

{pstd}
The defaults are the CMS Chronic Conditions Warehouse (CCW) Part D names, so Medicare files need no name options.
For other sources, map your variables with {opt person()}, {opt srvcdt()}, {opt qty()}, {opt days()},
{opt gnn()}, {opt bn()} and {opt strength()}. Names are matched case-insensitively.

{pstd}
{bf:Files with only an NDC.} The classes match on drug names, so if your claims carry only an NDC,
first merge generic name, brand name and strength from an NDC drug file onto the claims (or onto a small NDC list),
e.g. the FDA NDC Directory or the drug reference file your data vendor supplies.

{pstd}
{bf:Strength in separate columns.} If strength is stored as a number plus a unit, combine them into text first,
e.g. {cmd:gen str24 strength = string(strnum) + " " + strunit}. Strength text drives MME and some class exclusions
(a {cmd:%} strength marks topical/ophthalmic products), so check the MME reason table and {opt saveclaims()}
output the first time you use a new source.

{pstd}
{bf:Person key and dates.} The person key must have the same name and type in the cohort and in the claim files
(rename one of them if needed). Dates must be Stata daily dates.


{title:Statistics}

{p2colset 9 20 22 2}{...}
{p2col:{cmd:any}}any fill with fill date in window (0/1){p_end}
{p2col:{cmd:n}}number of fills{p_end}
{p2col:{cmd:days}}sum of days supplied{p_end}
{p2col:{cmd:qty}}sum of quantity dispensed{p_end}
{p2col:{cmd:first}/{cmd:last}}day (relative to index) of first / last fill in window{p_end}
{p2col:{cmd:cov}}distinct days covered in window, counting supply carried over from earlier fills (no stockpiling shift){p_end}
{p2col:{cmd:pdc}}{cmd:cov} / window length{p_end}
{p2col:{cmd:mme}}total MME dispensed (qty x MME per unit) by fills in window{p_end}
{p2col:{cmd:mmeday}}{cmd:mme} / window length (average daily MME){p_end}
{p2col:{cmd:mmemax}}highest daily MME of any single fill (qty x MME per unit / days){p_end}
{p2colreset}{...}


{title:Class library}

{pstd}
{cmd:pdemeds, listclasses} lists the built-in classes. Opioids, NSAIDs (systemic, non-selective, COX-2, topical),
gabapentinoids, muscle relaxants, benzodiazepines, Z-drugs, antidepressants (any/SSRI/SNRI/TCA),
antipsychotics, systemic corticosteroids (all, or the core four: {cmd:cortico_core}), PPIs, smoking cessation,
DMARDs ({cmd:dmard_cs}, {cmd:dmard_bio}, {cmd:dmard_tnf}, {cmd:dmard_il}, {cmd:dmard_ts} [JAK], {cmd:dmard_bts}, {cmd:dmard_any}), oral/IV bisphosphonates, denosumab,
osteoanabolics, SERMs, estrogens, aromatase inhibitors, diabetes classes, anticoagulants (any/DOAC/warfarin/injectable),
antiplatelets, statins, ACEi, ARB, beta blockers, CCB and diuretics.

{pstd}
Each class has an {it:include} and an {it:exclude} regex (ICU syntax, {cmd:ustrregexm()}). They are matched
against the upper-case string {cmd:" GNN | BN | STR | FORM "}, so a regex can test the strength.
For example, {cmd:%} in the strength flags topical or ophthalmic products, and {cmd:3 ?MG/3 ?ML} flags IV ibandronate.
Generic names are US (USAN) names.

{pstd}
To change or add classes, export the library, edit the CSV, and pass it back:

{phang2}{cmd:. pdemeds, exportclasses(classes.csv)}{p_end}
{phang2}{cmd:. pdemeds, files(...) id(...) index(...) deffile(classes.csv) classes(opioid myclass)}{p_end}

{pstd}
Rows in {opt deffile()} replace library rows with the same {it:class} name. Columns are class, label, include, exclude.
Class names must be valid Stata names of at most 16 characters.

{pstd}
{bf:Always audit new data}: use {opt saveclaims()} and {cmd:tab gnn if c_}{it:class} to review what each class captured.


{title:MME}

{pstd}
MME per dispensed unit comes from {help pdemme}. It finds the opioid ingredient in the generic name, picks that
ingredient's number from the strength text, converts liquids to per mL, and handles patches
(fentanyl: mcg/hr x 2.4 x 3 days; buprenorphine: mcg/hr x 1.8 x 7 days per patch). It then applies the factors in {opt mmecf()}:

{p2colset 9 32 34 2}{...}
{p2col:{cmd:cdc2022}}hydromorphone 5, methadone 4.7, tramadol 0.2 (CDC 2022 guideline){p_end}
{p2col:{cmd:cdc2016}}hydromorphone 4, methadone 3, tramadol 0.1{p_end}
{p2col:both}hydrocodone 1, oxycodone 1.5, morphine 1, oxymorphone 3, codeine 0.15, tapentadol 0.4,
meperidine 0.1, levorphanol 11, pentazocine 0.37, dihydrocodeine 0.25, fentanyl buccal 0.13 / nasal 0.16 (per mcg),
buprenorphine buccal film 0.03 (per mcg){p_end}
{p2colreset}{...}

{pstd}
Quantity must be in dispensing units (tablets, mL, patches). Claims that cannot be parsed get missing MME; the
summary table shows how many, with reasons.
If you have an NDC-level crosswalk, pass it in {opt mmefile()}. It needs a variable {cmd:ndc} (11-digit) and either
{cmd:mme_per_unit}, or {cmd:strength_per_unit} and {cmd:mme_cf}. It also needs {opt ndc()} in the claim files.


{title:Examples}

{pstd}Medicare Part D files (default variable names){p_end}

{phang2}{cmd:. use studycohort, clear}{p_end}
{phang2}{cmd:. local rx PDE16 PDE17 PDE18 PDE19 PDE20 PDE21}{p_end}
{phang2}{cmd:. pdemeds, files(`rx') id(link) index(indexadm) classes(nsaid nsaid_nonsel nsaid_cox2 opioid) ///}{p_end}
{phang3}{cmd:windows(pre:-89/-1 post:0/365 p45:0/45 p90:0/90) stats(any n qty days mme mmeday) mmecf(cdc2016)}{p_end}
{phang2}{cmd:. pdemeds, files(`rx') id(link) index(indexdis) ///}{p_end}
{phang3}{cmd:classes(bisphos_oral bisphos_iv denosumab osteo_anabolic serm estrogen glp1ra anticoag) ///}{p_end}
{phang3}{cmd:windows(pre:-89/-1 pre12:-364/-1 post:0/365 p90:0/90) stats(any n first)}{p_end}

{pstd}Another data source with its own variable names (generic name and strength merged from an NDC drug file){p_end}

{phang2}{cmd:. use studycohort, clear}{p_end}
{phang2}{cmd:. pdemeds, files(rx_claims_2019 rx_claims_2020) id(episode_id) person(patient_id) index(surgery_dt) ///}{p_end}
{phang3}{cmd:srvcdt(fill_dt) qty(quantity) days(days_supply) gnn(generic_name) bn(brand_name) strength(strength) ///}{p_end}
{phang3}{cmd:classes(opioid benzo gabapentinoid) windows(pre:-90/-1 post:0/90) stats(any n mme mmeday)}{p_end}

{pstd}DMARD exposure groups (conventional only vs biologic/targeted synthetic){p_end}

{phang2}{cmd:. pdemeds, files(`rx') id(link) index(indexadm) ///}{p_end}
{phang3}{cmd:classes(dmard_cs dmard_bts dmard_tnf dmard_ts cortico_core) ///}{p_end}
{phang3}{cmd:windows(pre90:-90/-1 pre180:-180/-1) stats(any n last)}{p_end}
{phang2}{cmd:. gen dmardgroup = cond(dmard_bts_pre180_any, 2, dmard_cs_pre180_any)}{p_end}

{pstd}
Infusions (infliximab, rituximab, IV abatacept, tocilizumab, golimumab) are usually billed on medical rather than pharmacy
claims; measure them with {help pbmeds} and combine.

{pstd}Chronic use at baseline, restricted to people with continuous pharmacy coverage{p_end}

{phang2}{cmd:. pdemeds, files(`rx') id(person_id) person(person_id) index(admit_dt) classes(opioid benzo gabapentinoid antidep) ///}{p_end}
{phang3}{cmd:windows(base:-180/-1 fu:1/180) stats(any n pdc mmeday) enrolled(rx_covered) prefix(rx_)}{p_end}
{phang2}{cmd:. gen chronic_opioid_base = rx_opioid_base_pdc >= 0.5}{p_end}


{title:Notes}

{pstd}
Windows are inclusive and based on fill date. Day 0 = index date.
"pre:-90/-1" is 90 days; a "> index-90" rule is 89 days ({cmd:-89/-1}).

{pstd}
Pharmacy claims capture outpatient dispensing only. Drugs given in clinics or hospital outpatient departments
(most IV bisphosphonates, denosumab, romosozumab, biologic infusions, injections) are under-ascertained;
add them from medical claims with {help pbmeds}. Inpatient medication use is not captured.

{pstd}
Over-the-counter purchases (aspirin, most NSAIDs and PPIs bought without a prescription) are not in claims data.
Some sources also lack claims for particular coverage arrangements (in Medicare, for example, months covered
through the retiree drug subsidy have no Part D event records).

{pstd}
Requires Stata 16+. {cmd:pdemme.ado} must be on the adopath for MME statistics (it is installed with the package).


{title:Medical-claims companion: pbmeds}

{pstd}Full documentation: {help pbmeds}.{p_end}

{pstd}
{cmd:pbmeds} measures provider-administered drugs and procedures from medical claims by HCPCS/CPT code.
It uses the same {opt id()}, {opt index()}, {opt windows()} and class names as {cmd:pdemeds}.
Statistics are {cmd:any n first last units}, where {cmd:n} counts distinct administration days.
Variables are prefixed {cmd:pb_} by default.
After running {cmd:pdemeds}, {opt combine(rx_)} creates pharmacy + medical-claims versions:
{cmd:any}=either source, {cmd:n}=pharmacy fills + administration days, {cmd:first}=earliest, {cmd:last}=latest.

{phang2}{cmd:. pbmeds, listclasses}{p_end}
{phang2}{cmd:. pdemeds, files(`rx') id(link) index(indexadm) classes(dmard_bio dmard_tnf) windows(pre180:-180/-1) stats(any n first)}{p_end}
{phang2}{cmd:. pbmeds, files(med2019 med2020) id(link) index(indexadm) ///}{p_end}
{phang3}{cmd:classes(dmard_bio dmard_tnf cortico_inj) windows(pre180:-180/-1) stats(any n first) combine(rx_)}{p_end}


{title:Testing}

{pstd}
The package includes a synthetic test suite (made-up data only). After {cmd:net install}, download it with
{cmd:net get pdemeds} (see Installation) and run {cmd:do pdemeds_test.do}. It checks {cmd:pdemme}, {cmd:pdemeds} and {cmd:pbmeds}
against hand-computed values and reports pass/fail for each check.
{cmd:net get} also downloads {cmd:pdemeds_classes.csv} and {cmd:pbmeds_classes.csv}, templates of the built-in class libraries for {opt deffile()}.


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
{p2col:{cmd:r(varlist)}}variables created{p_end}
{p2col:{cmd:r(classes)}}classes used{p_end}
{p2col:{cmd:r(windows)}}windows{p_end}
{p2col:{cmd:r(stats)}}statistics{p_end}
{p2col:{cmd:r(N_claims)}}flagged claims (incl. carry-over){p_end}
{p2colreset}{...}


{title:Author}

{pstd}
Brook I. Martin, PhD MPH{break}
University of Utah{break}
{browse "https://github.com/BrookMartin/pdemeds"}{break}
Please report problems or suggestions at {browse "https://github.com/BrookMartin/pdemeds/issues"}.


{title:Also see}

{psee}
{help pbmeds} (medical claims, HCPCS/CPT), {help pdemme} (MME per dispensed unit)
{p_end}
