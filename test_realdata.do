*------------------------------------------------------------------------------*
* Test programs with procurement dataset
* Alvaro Carril
*------------------------------------------------------------------------------*

clear all

// Set root directory
if "`c(os)'" == "MacOSX" cd "/Users/alvaro/Library/Application Support/Stata/ado/personal/rddsga/"
if "`c(os)'" == "Windows" cd "C:\ado\personal\rddsga"

// Set adopath and discard loaded programs
*adopath + old_ados/balancepscore
discard

// Load dataset
use data/procurement_test3, clear

// Run command
rddsga ///
sh_licitacion high_direct /// outcome and treatvar
p1 p2 p3 sh_licitacionPRE2 sh_directoPRE1 sh_licitacionPRE1 sh_directoPRE2 size_PRE1 size_PRE2 I_PREaudit /// covariates
if (dis_cutoff2>-4 & dis_cutoff2<4), ///
  psweight(peso) pscore(ps_flexmodel41) comsup(soporte) logit ///
  balvars(p1 p2 p3 size_PRE1 size_PRE2 audited dTR1-dTR3 Year2 Year1 Zone1-Zone3)
*return list
