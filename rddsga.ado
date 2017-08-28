*! 0.9 Alvaro Carril 25aug2017
program define rddsga, eclass
version 11.1
syntax varlist(min=2 numeric fv) [if] [in] , ///
  SGroup(name) BWidth(real) [ Treatment(name) Cutoff(real 0) /// important inputs
  	ipsweight(name) PSCore(name) COMsup(name) noCOMsupaux /// newvars
    BALance(varlist numeric) DIBALance probit /// balancepscore opts
    IVregress REDUCEDform FIRSTstage vce(string) QUADratic /// model opts
    nobootstrap bsreps(real 50) noipsw ] // bootstrap options

*-------------------------------------------------------------------------------
* Check inputs
*-------------------------------------------------------------------------------

// Check that depvar and assignvar are not factor variables
local fvops = "`s(fvops)'" == "true" | _caller() >= 11 
if `fvops' { 
  local vv: di "version " ///
  string(max(11,_caller())) ", missing: " 
  gettoken first rest : varlist
  gettoken second rest : rest
  _fv_check_depvar `first'
  capture _fv_check_depvar `second'
  if _rc!=0 {
    di as error "assignvar {bf:`second'} may not be a factor variable"
    exit 198
  }
}

// Check that treatment() is specified if ivregress is specified
if "`ivregress'" != "" & "`treatment'" == "" {
  di as error "treatment() must be specified with ivregress"
  exit 198
}

// ipsweight(): define new propensity score weighting variable or use a tempvar
if "`ipsweight'" != "" confirm new variable `ipsweight'
else tempvar ipsweight

// comsup(): define new common support variable or use a tempvar
if "`comsup'" != "" confirm new variable `comsup'
else tempvar comsup

// pscore(): define new propensity score variable or use a tempvar
if "`pscore'" != "" confirm new variable `pscore'
else tempvar pscore

// Issue warning if no covariates and no vars in balance
if `: list sizeof varlist'<=2 & `: list sizeof balance'==0 {
  di as error "either {it:indepvars} or {bf:balance()} must be specified"
  exit 198
}


*-------------------------------------------------------------------------------
* Process inputs
*-------------------------------------------------------------------------------

// Mark observations to be used
marksample touse, novarlist

// Extract outcome variable
local depvar : word 1 of `varlist'

// Extract assignment variable
local assignvar :	word 2 of `varlist'

// Define covariates list
local covariates : list varlist - depvar
local covariates : list covariates - assignvar

// Add c. stub to continuous covariates for factor interactions
foreach var in `covariates' {
  capture _fv_check_depvar `var'
  if _rc != 0 local fv_covariates `fv_covariates' `var'
  else local fv_covariates `fv_covariates' c.`var'
}

// Create complementary sgroup var
tempvar sgroup0
qui gen `sgroup0' = (`sgroup' == 0) if !mi(`sgroup')

// Extract balance variables
if "`balance'" == "" local balance `covariates'
local n_balance `: word count `balance''

// Define model to fit (logit is default)
if "`probit'" != "" local binarymodel probit
else local binarymodel logit

// Create bandwidth condition 
local bwidthtab `bwidth'
local bwidth abs(`assignvar') < `bwidth'

// Create indicator cutoff variable
*tempvar cutoffvar
*gen _cutoff = (`assignvar'>`cutoff')
*lab var _cutoff "Treatment"
confirm new variable _cutoff
gen _cutoff = (`assignvar'>`cutoff')

// Compute spline options
if "`quadratic'" != "" {
  local spline Quadratic
  tempvar assignXcutoff
  gen `assignXcutoff' = `assignvar'*_cutoff
  local quad c.`assignvar'#c.`assignvar' c.`assignXcutoff'#c.`assignXcutoff'
}
else local spline Linear

// Create weight local for regression
if "`ipsw'" == "noipsw" local weight = ""
else local weight "[pw=`ipsweight']"

*-------------------------------------------------------------------------------
* Compute balance table matrices
*-------------------------------------------------------------------------------

* Original balance
*-------------------------------------------------------------------------------
// Compute balanace matrix 
balancematrix, matname(unw)  ///
  touse(`touse') bwidth(`bwidth') balance(`balance') ///
  sgroup(`sgroup') sgroup0(`sgroup0') n_balance(`n_balance')
// Store balance matrix and computed balance stats
matrix unw = e(unw)
foreach s in unw_N_G0 unw_N_G1 unw_pvalue unw_Fstat unw_avgdiff {
  scalar `s' = e(`s')
}
// Display balance matrix and balance stats
if "`dibalance'" != "" {
  di _newline as result "Unweighted"
  matlist unw, ///
    border(rows) format(%9.3g) noblank
  di "Obs. in subgroup 0: " unw_N_G0
  di "Obs. in subgroup 1: " unw_N_G1
  di "Mean abs(std_diff): " unw_avgdiff
  di "F-statistic: " unw_Fstat
  di "Global p-value: " unw_pval_global
}

* Propensity Score Weighting balance
*-------------------------------------------------------------------------------
// Compute balanace matrix 
balancematrix, matname(ipsw)  ///
  psw ipsweight(`ipsweight') touse(`touse') bwidth(`bwidth') balance(`balance') ///
  pscore(`pscore') comsup(`comsup') comsupaux(`comsupaux') binarymodel(`binarymodel') ///
	sgroup(`sgroup') sgroup0(`sgroup0') n_balance(`n_balance') 
// Store balance matrix and computed balance stats
matrix ipsw = e(ipsw)
foreach s in ipsw_N_G0 ipswN_G1 ipsw_pvalue ipsw_Fstat ipsw_avgdiff {
  scalar `s' = e(`s')
}
// Display balance matrix and balance stats
if "`dibalance'" != "" {
  di _newline as result "Inverse Propensity Score Weighting"
  matlist ipsw, ///
  border(rows) format(%9.3g) noblank
  di "Obs. in subgroup 0: " ipsw_N_G0
  di "Obs. in subgroup 1: " ipsw_N_G1
  di "Mean abs(std_diff): " ipsw_avgdiff
  di "F-statistic: " ipsw_Fstat
  di "Global p-value: " ipsw_pval_global
}

*-------------------------------------------------------------------------------
* Model
*-------------------------------------------------------------------------------

* First stage
*-------------------------------------------------------------------------------
if "`firststage'" != "" {
  // Regression
  qui reg `treatment' i.`sgroup'#1._cutoff i.`sgroup' ///
    i.`sgroup'#(`fv_covariates' c.`assignvar' c.`assignvar'#_cutoff `quad') ///
    `weight' if `touse' & `bwidth', vce(`vce')
  // Compute bootstrapped variance-covariance matrix and post results
  if "`bootstrap'" != "nobootstrap" myboo `sgroup' _cutoff `bsreps'
  // If no bootstrap, trim b and V to show only RD estimates
  else epost `sgroup' _cutoff 
}

* Reduced form
*-------------------------------------------------------------------------------
if "`reducedform'" != "" {
  // Regression
  qui reg `depvar' i.`sgroup'#1._cutoff i.`sgroup' ///
    i.`sgroup'#(`fv_covariates' c.`assignvar' c.`assignvar'#_cutoff `quad') ///
    `weight' if `touse' & `bwidth', vce(`vce')
  // Compute bootstrapped variance-covariance matrix and post results
  if "`bootstrap'" != "nobootstrap" myboo `sgroup' _cutoff `bsreps'
  // If no bootstrap, trim b and V to show only RD estimates
  else epost `sgroup' _cutoff 
}

* Instrumental variables
*-------------------------------------------------------------------------------
if "`ivregress'" != "" {
  // Regression
  qui ivregress 2sls `depvar' i.`sgroup' ///
    i.`sgroup'#(`fv_covariates' c.`assignvar' c.`assignvar'#_cutoff `quad') ///
    (i.`sgroup'#1.`treatment' = i.`sgroup'#_cutoff) ///
    `weight' if `touse' & `bwidth', vce(`vce')
  // Compute bootstrapped variance-covariance matrix and post results
  if "`bootstrap'" != "nobootstrap" myboo `sgroup' `treatment' `bsreps'
  // If no bootstrap, trim b and V to show only RD estimates
  else epost `sgroup' `treatment'
}

* Post and display balance results
*-------------------------------------------------------------------------------
// Post global balance stats
foreach w in unw ipsw {
  foreach s in N_G0 N_G1 pvalue Fstat avgdiff {
    ereturn scalar `w'_`s' = `w'_`s'
  }
}
// Post balance matrices
ereturn matrix ipsw ipsw
ereturn matrix unw unw

* Post and display estimation results
*-------------------------------------------------------------------------------
if "`ivregress'" != "" | "`reducedform'" != "" | "`firststage'" != "" {
  // Post abridged b and V matrices
  mat list b
  ereturn repost b=b V=V, resize
  // Display estimates by subgroup
  di as result "Subgroup estimates"
  ereturn display
  // Display difference of subgroup estimates 
  di _newline as result "Difference"
  di as text "_nl_1 = _b[1.`sgroup'#1._cutoff] - _b[0.`sgroup'#1._cutoff]" _continue
  if "`ivregress'" == "" nlcom _b[1.`sgroup'#1._cutoff] - _b[0.`sgroup'#1._cutoff], noheader
  else nlcom _b[1.`sgroup'#1.`treatment'] - _b[0.`sgroup'#1.`treatment'], noheader
}

end

*===============================================================================
* Define auxiliary subroutines
*===============================================================================

*-------------------------------------------------------------------------------
* epost: post matrices in e(b) and e(V); leave other ereturn results unchanged
*-------------------------------------------------------------------------------
program epost, eclass
  // Store results: scalars
  local scalars: e(scalars)
  foreach scalar of local scalars {
    local `scalar' = e(`scalar')
  }
  // Store results: macros
  local macros: e(macros)
  foreach macro of local macros {
    local `macro' = e(`macro')
  }
  // Store results: matrices (drop V_modelbased; b and V are computed below)
  local matrices: e(matrices)
  // Store results: functions
  tempvar esample
  gen `esample' = e(sample)
  // b and V matrices
  matrix b = e(b)
  matrix V = e(V)
  matrix b = b[1, "0.`1'#1.`2'".."1.`1'#1.`2'"]
  matrix V = V["0.`1'#1.`2'".."1.`1'#1.`2'", "0.`1'#1.`2'".."1.`1'#1.`2'"]
  ereturn post, esample(`esample')
  // Post results: scalars
  foreach scalar of local scalars {
    ereturn scalar `scalar' = ``scalar''
  }
  // Post results: macros
  foreach macro of local macros {
    ereturn local `macro' ``macro''
  }
end

*-------------------------------------------------------------------------------
* myboo: compute bootstrapped variance-covariance matrix & adjust ereturn results
*-------------------------------------------------------------------------------
program myboo, eclass
  // Store results: scalars
  local scalars: e(scalars)
  foreach scalar of local scalars {
    local `scalar' = e(`scalar')
  }
  // Store results: macros
  local macros: e(macros)
  foreach macro of local macros {
    local `macro' = e(`macro')
  }
  // Store results: matrices (drop V_modelbased; b and V are computed below)
  local matrices: e(matrices)
  // Store results: functions
  tempvar esample
  gen `esample' = e(sample)
  // Extract b submatrix with subgroup coefficients
  matrix b = e(b)
  matrix b = b[1, "0.`1'#1.`2'".."1.`1'#1.`2'"]
  mat colnames b = 0.`1'#1.`2' 1.`1'#1.`2'
  // Start bootstrap 
  di ""
  _dots 0, title(Bootstrap replications) reps(`3')
  forvalues i=1/`3' {
    preserve
    bsample  // sample w/ replacement; default sample size is _N
    qui `e(cmdline)' // use full regression specification left out by reg
    mat this_run = (_b[0.`1'#1.`2'], _b[1.`1'#1.`2'])
    mat cumulative = nullmat(cumulative) \ this_run
    restore
    _dots `i' 0
  }
  di _newline
  // Compute variance-covariance matrix 
  /* This procedure was achieved with the variance mata function, but could be 
  computed with cross() or crossdev() mata functions. */
  mata: cumulative = st_matrix("cumulative")
  mata: st_matrix("V", variance(cumulative)) // see help mf_mean
  mat rownames V = 0.`1'#1.`2' 1.`1'#1.`2'
  mat colnames V = 0.`1'#1.`2' 1.`1'#1.`2'
  // Return 
  ereturn post, esample(`esample')
  // Post results: scalars
  foreach scalar of local scalars {
    ereturn scalar `scalar' = ``scalar''
  }
  ereturn scalar N_reps = `3'
  ereturn scalar level = 95
  // Post results: macros
  foreach macro of local macros {
    if "`macro'" == "clustvar" continue // skip this macro as it doesn't apply
    ereturn local `macro' ``macro''
  }
  ereturn local vcetype "Bootstrap"
  ereturn local vce "bootstrap"
  ereturn local prefix "bootstrap"

end

*-------------------------------------------------------------------------------
* nlcompost: modify b matrix after nlcom
*-------------------------------------------------------------------------------
program nlcompost, eclass
  matrix b = e(b)
  matrix colnames b = Difference 
  ereturn repost b = b, rename // renames V matrix as well
end

*-------------------------------------------------------------------------------
* nlcomhack: hack b and V matrices to inlude nlcom results
*-------------------------------------------------------------------------------
program nlcomhack, eclass
  tempname b V nlcom_V
  matrix `b' = e(b)
  matrix `V' = e(V)
  local i = colnumb(`b', "_nl_1")
  qui nlcom _b[1.`1'#1.`2'] - _b[0.`1'#1.`2']
  matrix `nlcom_V' = r(V) // for some reason this is necessary
  matrix `b'[1,`i'] = r(b)
  matrix `V'[`i',`i'] = `nlcom_V'[1,1] // ...and this
  ereturn repost b = `b' V = `V'
end


*-------------------------------------------------------------------------------
* balancematrix: compute balance table matrices and other statistics
*-------------------------------------------------------------------------------
program define balancematrix, eclass
syntax, matname(string) /// important inputs, differ by call
  touse(name) bwidth(string) balance(varlist) /// unchanging inputs
  [psw ipsweight(name) pscore(name) comsup(name) comsupaux(string) binarymodel(string)] /// only needed for PSW balance
  sgroup(name) sgroup0(name) n_balance(int) // todo: eliminate these? can be computed by subroutine at low cost

* Create variables specific to PSW matrix
*-------------------------------------------------------------------------------
if "`psw'" != "" { // if psw
  // Fit binary response model
  qui `binarymodel' `sgroup' `balance' if `touse' & `bwidth'

  // Generate pscore variable and clear stored results
  qui predict double `pscore' if `touse' & `bwidth' & !mi(`sgroup')
  ereturn clear

  // Compute common support area by default; if not, equal comsup to 1
  if "`comsupaux'" != "nocomsupaux" {
    qui sum `pscore' if `sgroup' == 1 /* todo: check why this is like that */
    qui gen `comsup' = ///
      (`pscore' >= `r(min)' & ///
       `pscore' <= `r(max)')
    label var `comsup' "Dummy for obs. in common support"
  }
  else qui gen `comsup' = 1 if `touse' & `bwidth' & !mi(`sgroup')

  // Count observations in each treatment group
  qui count if `touse' & `bwidth' & `comsup' & `sgroup'==0
  local N_G0 = `r(N)'
  qui count if `touse' & `bwidth' & `comsup' & `sgroup'==1
  local N_G1 = `r(N)'

  // Compute propensity score weighting vector
  cap drop `ipsweight'
  qui gen `ipsweight' = ///
    `N_G1'/(`N_G1'+`N_G0')/`pscore'*(`sgroup'==1) + ///
    `N_G0'/(`N_G1'+`N_G0')/(1-`pscore')*(`sgroup'==0) ///
    if `touse' & `bwidth' & `comsup' & !mi(`sgroup')
} // end if psw

* Count obs. in each treatment group if not PSW matrix
*-------------------------------------------------------------------------------
else { // if nopsw
  qui count if `touse' & `bwidth' & `sgroup'==0
  local N_G0 = `r(N)'
  qui count if `touse' & `bwidth' & `sgroup'==1
  local N_G1 = `r(N)'
} // end if nopsw

* Compute stats specific for each covariate 
*-------------------------------------------------------------------------------
local j = 0
foreach var of varlist `balance' {
  local ++j

  // Compute and store conditional expectations
  if "`psw'" == "" qui reg `var' `sgroup0' `sgroup' if `touse' & `bwidth', noconstant /* */
  else qui reg `var' `sgroup0' `sgroup' [iw=`ipsweight'] if `touse' & `bwidth' & `comsup', noconstant
  local coef`j'_G0 = _b[`sgroup0']
  local coef`j'_G1 = _b[`sgroup']

  // Compute and store mean differences and their p-values
  if "`psw'" == "" qui reg `var' `sgroup0' if `touse' & `bwidth'
  else qui reg `var' `sgroup0' [iw=`ipsweight'] if `touse' & `bwidth' & `comsup'
  matrix m = r(table)
  scalar diff`j'=m[1,1] // mean difference
  local pval`j' = m[4,1] // p-value 

  // Standardized mean difference
  if "`psw'" == "" qui summ `var' if `touse' & `bwidth' & !mi(`sgroup')
  else qui summ `var' if `touse' & `bwidth' & `comsup' & !mi(`sgroup')
  local stddiff`j' = (diff`j')/r(sd)
}

* Compute global stats
*-------------------------------------------------------------------------------
// Mean of absolute standardized mean differences (ie. stddiff + ... + stddiff`k')
/* todo: this begs to be vectorized */
local avgdiff = 0
forvalues j = 1/`n_balance' {
  local avgdiff = abs(`stddiff`j'') + `avgdiff' // sum over `j' (balance)
}
local avgdiff = `avgdiff'/`n_balance' // compute mean 

// F-statistic and global p-value
if "`psw'" == "" qui reg `sgroup' `balance' if `touse' & `bwidth'
else qui reg `sgroup' `balance' [iw=`ipsweight'] if `touse' & `bwidth' & `comsup' 
local Fstat = e(F)
local pval_global = 1-F(e(df_m),e(df_r),e(F))

* Create balance matrix
*-------------------------------------------------------------------------------
// Matrix parameters
matrix `matname' = J(`n_balance', 4, .)
matrix colnames `matname' = mean_G0 mean_G1 std_diff p-value
matrix rownames `matname' = `balance'

// Add per-covariate values 
forvalues j = 1/`n_balance' {
  matrix `matname'[`j',1] = `coef`j'_G0'
  matrix `matname'[`j',2] = `coef`j'_G1'
  matrix `matname'[`j',3] = `stddiff`j''
  matrix `matname'[`j',4] = `pval`j''
}

// Return matrix and other scalars
scalar `matname'_N_G0 = `N_G0'
scalar `matname'_N_G1 = `N_G1'
scalar `matname'_avgdiff = `avgdiff'
scalar `matname'_Fstat = `Fstat'
scalar `matname'_pval_global = `pval_global'

ereturn matrix `matname' = `matname', copy
ereturn scalar `matname'_avgdiff = `avgdiff'
ereturn scalar `matname'_Fstat = `Fstat'
ereturn scalar `matname'_pvalue = `pval_global'
ereturn scalar `matname'_N_G1 = `N_G1'
ereturn scalar `matname'_N_G0 = `N_G0'

end

********************************************************************************

/* 
CHANGE LOG
0.9
  - Compute bootstrapped variance-covariance matrix
  - Make program (and subprograms) e-class
  - Allow issuing no model
0.8
  - Add synthetic dataset for examples
0.7 
  - First alpha version ready for full usage
  - Implement nlcom hack to all models, detect diff coef position automatically
0.6
  - Implement nlcom hack to show difference as additional coefficient in ivreg
0.5
  - Fist working version with IVREG, reduced form and first stage equations
  - Implement output reporting with estimates table and estout
  - Default binarymodel is logit
0.4
  - First working version with IVREG equation
0.3
  - Standardize syntax to merge with original rddsga.ado
0.2
  - Implement balancematrix as separate subroutine
  - Standardize balancematrix output
0.1
	- First working version, independent of project
	- Remove any LaTeX output
	- Modify some option names and internal locals

KNOWN ISSUES/BUGS:
  - Should we use pweights or iweights? iw don't work with ivregress.

TODOS AND IDEAS:
  - Create subroutine of matlist formatting for display of balancematrix output
  - Implement matrix manipulation in Mata
  - Get rid of sgroup0 hack
  - Allow that groupvar is not necessarily an indicator variable
  - Is it possible to allow for N subgroups?
*/
