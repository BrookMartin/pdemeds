{smcl}
{* *! version 1.0.0  20nov2026}{...}
{title:Title}

{phang}
{bf:pdemme} {hline 2} Morphine milligram equivalents (MME) per dispensed unit from drug name and strength text


{title:Syntax}

{p 8 16 2}
{cmd:pdemme} {cmd:,} {opt gnn(varname)} {opt str:ength(varname)} {opt gen:erate(newvar)} [{it:options}]

{synoptset 24 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Required}
{synopt:{opt gnn(varname)}}generic drug name (string), e.g. {cmd:gnn} in Medicare Part D files{p_end}
{synopt:{opt str:ength(varname)}}strength text (string), e.g. {cmd:str} in Medicare Part D files{p_end}
{synopt:{opt gen:erate(newvar)}}MME per dispensed unit{p_end}

{syntab:Options}
{synopt:{opt cf(cdc2022|cdc2016)}}conversion-factor set (default {cmd:cdc2022}){p_end}
{synopt:{opt ing:redient(newvar)}}opioid ingredient detected (blank if not an opioid){p_end}
{synopt:{opt reas:on(newvar)}}"ok", or why no MME could be assigned{p_end}
{synopt:{opt bup:oud(#)}}MME per mg for buprenorphine products dosed in mg (default: not assigned){p_end}
{synopt:{opt replace}}overwrite the generated variables if they exist{p_end}
{synoptline}


{title:Description}

{pstd}
{cmd:pdemme} converts drug descriptions (generic name + strength text) from any pharmacy claims or
dispensing data into MME per dispensed unit: per tablet or capsule, per mL of liquid, per transdermal patch,
per buccal film or lozenge, or per nasal spray.
From that, fill-level measures follow directly:

{phang2}total MME of a fill = quantity dispensed x MME per unit{p_end}
{phang2}daily MME of a fill = quantity dispensed x MME per unit / days supplied{p_end}

{pstd}
Quantity must be in the same dispensing units (tablets, mL, patches, films, sprays).

{pstd}
It is used internally by {help pdemeds} (stats {cmd:mme}, {cmd:mmeday}, {cmd:mmemax}) and can be called from
your own do-files, or run on its own.

{pstd}
{bf:Run it on distinct drug descriptions, not claims.} Keep the unique name x strength combinations,
run {cmd:pdemme}, and merge the result back {cmd:m:1} on {it:gnn str} (see Examples). This is much faster
and gives you a short table to review.


{title:Data from other sources}

{pstd}
Generic names should be US (USAN) names, as in most US claims and drug reference files. Strength is read as text in the
common formats {cmd:"10MG-325MG"}, {cmd:"5 MG/5 ML"}, {cmd:"25 MCG/HR"}; case and spacing do not matter.
If your data store strength as a number and a unit in separate columns, combine them into one text variable first
(e.g. {cmd:gen str24 strength = string(strnum) + " " + strunit}). If your claims carry only an NDC, merge generic name and
strength from an NDC drug file before running {cmd:pdemme}. Check the {opt reason()} table the first time you use a new source.


{title:How strength is parsed}

{pstd}Spaces are removed from the strength text first. Then:{p_end}

{phang2}1. {bf:Ingredient.} The opioid is found in {it:gnn}. Names that contain other names are tested first
(dihydrocodeine before codeine, benzhydrocodone before hydrocodone). Apomorphine is not treated as morphine.{p_end}

{phang2}2. {bf:Combination products.} The opioid's position among the ingredients in {it:gnn}
(split on {cmd:/}, {cmd:-} and {cmd:WITH}) picks the matching hyphen-separated number in the strength.
For example, ACETAMINOPHEN WITH CODEINE, "300-30 MG", gives 30 mg codeine.{p_end}

{phang2}3. {bf:Liquids.} "A MG/B ML", "A MG/ML" and truncated forms such as "7.5-325/15" give A/B mg per mL,
so the quantity for liquids must be in mL.{p_end}

{phang2}4. {bf:Patches} ("MCG/HR"). Fentanyl: mcg/hr x 2.4 x 3 days per patch (= x 7.2).
Buprenorphine: mcg/hr x 1.8 x 7 days per patch (= x 12.6).{p_end}

{phang2}5. {bf:Other mcg products.} Fentanyl buccal/sublingual/lozenge x 0.13 per mcg; fentanyl nasal spray x 0.16 per mcg;
buprenorphine buccal film (e.g. Belbuca) x 0.03 per mcg.{p_end}

{phang2}6. {bf:Not assigned.} Buprenorphine dosed in mg (sublingual/injectable products for opioid use disorder) gets no MME,
following CDC guidance; use {opt bupoud()} to override. Injectable fentanyl (mcg/mL) also gets none.{p_end}


{title:Conversion factors (MME per mg unless noted)}

{p2colset 9 30 32 2}{...}
{p2col:{it:ingredient}}{cmd:cdc2022}   {cmd:cdc2016}{p_end}
{p2line}
{p2col:hydromorphone}5         4{p_end}
{p2col:methadone}4.7       3{p_end}
{p2col:tramadol}0.2       0.1{p_end}
{p2line}
{p2col:{it:same in both}}{p_end}
{p2col:hydrocodone}1{p_end}
{p2col:oxycodone}1.5{p_end}
{p2col:morphine}1{p_end}
{p2col:oxymorphone}3{p_end}
{p2col:codeine}0.15{p_end}
{p2col:dihydrocodeine}0.25{p_end}
{p2col:tapentadol}0.4{p_end}
{p2col:meperidine}0.1{p_end}
{p2col:levorphanol}11{p_end}
{p2col:pentazocine}0.37{p_end}
{p2col:opium}1{p_end}
{p2col:fentanyl patch}7.2 per mcg/hr per patch{p_end}
{p2col:fentanyl buccal/SL}0.13 per mcg{p_end}
{p2col:fentanyl nasal}0.16 per mcg{p_end}
{p2col:buprenorphine patch}12.6 per mcg/hr per patch{p_end}
{p2col:buprenorphine film}0.03 per mcg{p_end}
{p2colreset}{...}

{pstd}
{cmd:cdc2022} follows the 2022 CDC Clinical Practice Guideline. {cmd:cdc2016} reproduces the earlier CDC/NDC-file
factors. The CDC cautions that methadone's conversion is
dose-dependent and that a single factor is an approximation.

{pstd}
Butorphanol and benzhydrocodone are detected but have no factor, so they appear with reason
"no conversion factor for ingredient". Supply values for them through an NDC crosswalk ({help pdemeds} {opt mmefile()}).


{title:Reason codes}

{p2colset 9 46 48 2}{...}
{p2col:ok}MME assigned{p_end}
{p2col:not an opioid}no opioid ingredient found{p_end}
{p2col:buprenorphine mg (MOUD): not assigned}see {opt bupoud()}{p_end}
{p2col:injectable mcg/mL: not assigned}injectable fentanyl{p_end}
{p2col:no conversion factor for ingredient}e.g. butorphanol, benzhydrocodone{p_end}
{p2col:strength not parsed}strength text in an unexpected format: review these{p_end}
{p2colreset}{...}


{title:Examples}

{pstd}Build an MME crosswalk from distinct drug descriptions and attach it to claims{p_end}

{phang2}{cmd:. use rx_claims, clear}    // here with Medicare Part D variable names{p_end}
{phang2}{cmd:. preserve}{p_end}
{phang2}{cmd:.     keep gnn str}{p_end}
{phang2}{cmd:.     duplicates drop}{p_end}
{phang2}{cmd:.     pdemme, gnn(gnn) strength(str) generate(mme_unit) ingredient(opioid) reason(mme_note)}{p_end}
{phang2}{cmd:.     keep if opioid != ""}{p_end}
{phang2}{cmd:.     tab mme_note}{p_end}
{phang2}{cmd:.     list gnn str mme_note if mme_note != "ok", noobs sep(0)}{p_end}
{phang2}{cmd:.     tempfile xw}{p_end}
{phang2}{cmd:.     save `xw'}{p_end}
{phang2}{cmd:. restore}{p_end}
{phang2}{cmd:. merge m:1 gnn str using `xw', keep(master match) nogen}{p_end}
{phang2}{cmd:. gen double mme_total = qty_dspnsd_num * mme_unit}{p_end}
{phang2}{cmd:. gen double mme_daily = mme_total / days_suply_num if days_suply_num > 0}{p_end}

{pstd}Compare the two factor sets{p_end}

{phang2}{cmd:. pdemme, gnn(gnn) strength(str) generate(mme22) cf(cdc2022)}{p_end}
{phang2}{cmd:. pdemme, gnn(gnn) strength(str) generate(mme16) cf(cdc2016)}{p_end}
{phang2}{cmd:. list gnn str mme22 mme16 if mme22 != mme16 & !missing(mme22), noobs}{p_end}


{title:Notes}

{pstd}
Always review rows whose reason is not "ok" the first time you run {cmd:pdemme} on a new data source or release.
Strength fields are sometimes short (Medicare Part D's is 10 characters) and can be truncated or written in unusual ways.

{pstd}
For an NDC-level conversion instead of text parsing, pass a crosswalk to {help pdemeds} via {opt mmefile()}.
It overrides {cmd:pdemme} wherever an NDC matches.

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

{p2colset 9 22 24 2}{...}
{p2col:{cmd:r(N_opioid)}}rows with an opioid ingredient{p_end}
{p2col:{cmd:r(N_ok)}}of those, rows with MME assigned{p_end}
{p2col:{cmd:r(cf)}}conversion-factor set used{p_end}
{p2colreset}{...}


{title:Author}

{pstd}
Brook I. Martin, PhD MPH{break}
University of Utah{break}
{browse "https://github.com/BrookMartin/pdemeds"}{break}
Please report problems or suggestions at {browse "https://github.com/BrookMartin/pdemeds/issues"}.


{title:Also see}

{psee}
{help pdemeds}, {help pbmeds}
{p_end}
