# pdemeds: medication exposure from pharmacy and medical claims in Stata

`pdemeds` is a Stata package for measuring medication exposure around an index
date (surgery, hospitalization, diagnosis, enrollment) in administrative claims or
other dispensing and encounter data.

| Command   | Input | What it does |
|-----------|-------|--------------|
| `pdemeds` | Pharmacy dispensing claims | Flags ~50 medication classes in any number of windows: any use, fills, days supplied, quantity, first/last fill, days covered, proportion of days covered (PDC), and opioid morphine milligram equivalents (total, average daily, peak) |
| `pbmeds`  | Medical claims coded with HCPCS/CPT | Provider-administered drugs and procedures (biologic DMARDs and other infusions, injectable steroids, epidural steroid injections, IV bone agents), with an option to combine results with `pdemeds` |
| `pdemme`  | Drug name + strength text | MME per dispensed unit (tablet, mL, patch, film, spray) using CDC 2022 or CDC 2016 conversion factors |

The commands were developed with Medicare claims, so their default variable names
are the CMS Chronic Conditions Warehouse (CCW) names. **They are not limited to
Medicare.** Any source with the required fields works once you map your variable
names with the command options: commercial claims, Medicaid, health-system or EHR
dispensing and procedure records, registries. See [Using other data sources](#using-other-data-sources).

The package contains **no patient data**; the test suite uses synthetic data only.

## Installation

Requires Stata 16 or later.

```stata
net install pdemeds, from("https://raw.githubusercontent.com/BrookMartin/pdemeds/main/") replace
```

To download the synthetic test suite and the editable class-definition templates into your current folder:

```stata
net get pdemeds, from("https://raw.githubusercontent.com/BrookMartin/pdemeds/main/")
do pdemeds_test.do
```

The test suite builds a small synthetic cohort plus pharmacy, professional and facility claim files. It runs all three commands and checks 79 results against values worked out by hand. It ends with `All checks passed.` or stops with the list of failures.

Help after installing: `help pdemeds`, `help pbmeds`, `help pdemme`.

### Updating and uninstalling

```stata
* update to the latest version on GitHub
net install pdemeds, from("https://raw.githubusercontent.com/BrookMartin/pdemeds/main/") replace

* check what is installed / remove
ado describe pdemeds
ado uninstall pdemeds
```

### Without net install

Download the repository (**Code → Download ZIP** at https://github.com/BrookMartin/pdemeds). Copy the `.ado` and `.sthlp` files into your PERSONAL ado folder (type `sysdir` in Stata to find it), or into your project folder.

## Quick start

Your data in memory: one row per person or episode, with a person key and a daily index date.

```stata
use studycohort, clear

* pharmacy claims: opioids, NSAIDs, gabapentinoids 90 days before and after the index date
pdemeds, files(rx2019 rx2020) id(episode_id) person(patient_id) index(surgery_dt)   ///
    srvcdt(fill_dt) qty(quantity) days(days_supply)                                  ///
    gnn(generic_name) bn(brand_name) strength(strength)                              ///
    classes(opioid nsaid gabapentinoid) windows(pre:-90/-1 post:0/90)                ///
    stats(any n days first mme mmeday pdc)

* medical claims: biologic DMARDs and epidural steroid injections, combined with pharmacy
pdemeds, files(rx2019 rx2020) id(episode_id) person(patient_id) index(surgery_dt)   ///
    srvcdt(fill_dt) qty(quantity) days(days_supply) gnn(generic_name) bn(brand_name) ///
    strength(strength) classes(dmard_bio dmard_tnf) windows(pre180:-180/-1) stats(any n first)
pbmeds,  files(prof2019 prof2020 facility2019 facility2020) id(episode_id)          ///
    person(patient_id) index(surgery_dt) hcpcs(proc_cd) datevars(svc_dt)             ///
    unitvars(units) classes(dmard_bio dmard_tnf esi) windows(pre180:-180/-1)         ///
    stats(any n first) combine(rx_)
```

With Medicare CCW files no name options are needed, e.g. `pdemeds, files(PDE2019 PDE2020) id(link) index(indexadm) classes(opioid) stats(any mme)`.

Each class × window × statistic becomes a variable `<prefix><class>_<window>_<stat>`, e.g. `opioid_pre_mmeday`, `pb_esi_pre180_any`, `rx_dmard_bio_pre180_any`.

## Using other data sources

| | `pdemeds` (pharmacy) | `pbmeds` (medical) |
|---|---|---|
| **Required fields** | person key, fill date, quantity, days supplied, generic name (text), strength (text) | person key, service date, HCPCS/CPT code |
| **Optional fields** | brand name, dosage form, NDC (for an NDC-level MME crosswalk) | units |
| **Name options** | `person() srvcdt() qty() days() gnn() bn() strength() form() ndc()` | `person() hcpcs() datevars() unitvars()` |
| **Defaults (Medicare CCW)** | `bene_id srvc_dt qty_dspnsd_num days_suply_num gnn bn str prod_srvc_id` | `bene_id hcpcs_cd line_1st_expns_dt rev_cntr_dt line_srvc_cnt rev_cntr_unit_cnt` |

Practical notes:

- **Claims with only an NDC.** Drug classes match on drug *names*. If your pharmacy claims carry only an NDC, merge generic name, brand name and strength from an NDC drug file first, e.g. the FDA NDC Directory or the drug reference file supplied with your data.
- **Strength in two columns.** Combine number and unit into text: `gen str24 strength = string(strnum) + " " + strunit`. Strength text drives MME and some exclusions (a `%` strength marks topical and ophthalmic products).
- **Names are US generic (USAN) names**, and medical-claims classes use US HCPCS Level II and CPT codes. Other coding systems need your own class definitions via `deffile()`.
- **Variable names** are matched case-insensitively; the person key must have the same name and type in the cohort and the claim files. Dates must be Stata daily dates.
- **Professional and facility claims.** Office-administered drugs are on professional claims; hospital outpatient and infusion-center drugs are usually on facility claims. Give `pbmeds` both. Files can use different date and unit names: for each file, the first variable found in `datevars()` / `unitvars()` is used.
- **Check the first run on a new source**: the MME reason table, `saveclaims()`, and `tab gnn if c_<class>` show what each class captured.

## How it works

- Each claim file is read once, keeping only the needed columns and the cohort's claims inside the widest window.
- Pharmacy classes are regular expressions matched against `" GNN | BN | STR | FORM "` (generic name, brand name, strength, optional dosage form). They run on the **distinct** drug descriptions, typically a few thousand, rather than on every claim, which keeps the commands fast on large files.
- Medical-claims classes are regular expressions on the HCPCS/CPT code; matching lines are filtered while the file is loaded.
- Windows are inclusive day ranges relative to the index date (day 0), based on fill or service date. `cov`/`pdc` count supply carried over from earlier fills.
- People with no qualifying claim get 0 (missing for `first`, `last`, `mmemax`). A 0 is only meaningful for people whose claims are fully captured over the window (continuous enrollment). Use `enrolled()` to set results to missing for everyone else.

## Class library

`pdemeds, listclasses` and `pbmeds, listclasses` show the built-in classes. The full definitions are also in `pdemeds_classes.csv` and `pbmeds_classes.csv`.

**Pharmacy (`pdemeds`):**
- Opioids (excluding buprenorphine for opioid use disorder) and buprenorphine for opioid use disorder
- NSAIDs: systemic, non-selective, COX-2 and topical
- Gabapentinoids, muscle relaxants, benzodiazepines, Z-drugs
- Antidepressants (any, SSRI, SNRI, TCA) and antipsychotics
- Corticosteroids, PPIs, smoking cessation
- Bone agents: oral and IV bisphosphonates, denosumab, osteoanabolics, SERMs
- Estrogens and aromatase inhibitors
- Diabetes classes
- Anticoagulants and antiplatelets
- Cardiovascular: statins, ACE inhibitors, ARBs, beta blockers, calcium channel blockers, diuretics
- DMARDs: conventional, biologic, TNF, IL, JAK

**Medical claims (`pbmeds`):**
- DMARDs, including infliximab and rituximab biosimilars
- Corticosteroids: core systemic and all injectable
- Epidural steroid injections, and facet / SI joint injections
- IV bisphosphonates, denosumab, osteoanabolics

To change or add classes, edit a copy of a CSV and pass it back. Rows replace built-in classes with the same name:

```stata
pdemeds, exportclasses(myclasses.csv)        // or start from pdemeds_classes.csv
* ...edit in Excel or a text editor...
pdemeds, files(...) id(...) index(...) deffile(myclasses.csv) classes(opioid myclass)
```

Audit what each class captured with `saveclaims()` before relying on a definition in new data.

## MME

`pdemme` finds the opioid ingredient in the generic name and reads its strength from the strength text. It handles combination products, liquids (per mL), transdermal patches, buccal/sublingual and nasal fentanyl, and buprenorphine films. It then applies CDC conversion factors:

- `cdc2022` (default): hydromorphone 5, methadone 4.7, tramadol 0.2
- `cdc2016`: hydromorphone 4, methadone 3, tramadol 0.1

Quantity must be in dispensing units (tablets, mL, patches). Buprenorphine for opioid use disorder gets no MME, following CDC guidance (option `bupoud()` overrides). Anything that can't be parsed is reported with a reason. An NDC-level crosswalk can be supplied with `pdemeds, mmefile()`.

## Important limitations

- **Pharmacy claims only see outpatient dispensing.** Infusions and clinic-administered drugs (infliximab, rituximab, IV zoledronic acid, denosumab, injectable steroids) are mostly billed on medical claims. Use `pbmeds`, with both professional and facility claims. Inpatient medication use is not captured by either command.
- **Over-the-counter drugs** (aspirin, most OTC NSAIDs and PPIs) are not in claims data.
- **Coverage gaps look like non-use.** Months without pharmacy or medical coverage in the data source have no claims; examples are Medicare Advantage enrollees in Medicare fee-for-service files, or Medicare retiree-drug-subsidy months in Part D. Restrict the cohort or use `enrolled()`.
- **Codes change over time.** The medical-claims library covers 2016–2021 HCPCS/CPT codes, including retired ones. Check the current code sets for other years.
- **Small-cell rules.** Many data use agreements (including CMS's) prohibit publishing small counts. The commands do not suppress cells; that is up to your output code.

## Files

| File | Purpose |
|------|---------|
| `pdemeds.ado`, `pdemeds.sthlp` | Pharmacy-claims command and help |
| `pbmeds.ado`, `pbmeds.sthlp`   | Medical-claims (HCPCS/CPT) command and help |
| `pdemme.ado`, `pdemme.sthlp`   | MME helper and help |
| `pdemeds_test.do`              | Synthetic test suite (`net get`) |
| `pdemeds_classes.csv`, `pbmeds_classes.csv` | Templates of the built-in class libraries for `deffile()` (`net get`; not needed to run the commands) |
| `stata.toc`, `pdemeds.pkg`     | Stata `net install` index files |

## Citation

If you use this package, please cite:

> Martin BI. pdemeds: medication exposure from pharmacy and medical claims in Stata. Version 1.0.0. University of Utah; 2026. https://github.com/BrookMartin/pdemeds

## Author

Brook I. Martin, PhD MPH, University of Utah

Please report problems or suggestions through [GitHub issues](https://github.com/BrookMartin/pdemeds/issues).

## License

MIT. See `LICENSE`.
