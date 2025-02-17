﻿* Encoding: UTF-8.

DEFINE base_prices(year_1=!tokens(1)
                  /year=!tokens(1)
                  /flow=!tokens(1)
                  /outlier_median_year_limit_upper=!tokens(1)
                  /outlier_median_year_limit_lower=!tokens(1)
                  /outlier_sd_limit_upper=!tokens(1)
                  /outlier_sd_limit_lower=!tokens(1)
                  )

DATASET CLOSE all.

GET FILE=!quote(!concat('data/',!flow,'_',!year_1,'Q1.sav')).
ADD FILES FILE=*
         /FILE=!quote(!concat('data/',!flow,'_',!year_1,'Q2.sav'))
         /FILE=!quote(!concat('data/',!flow,'_',!year_1,'Q3.sav'))
         /FILE=!quote(!concat('data/',!flow,'_',!year_1,'Q4.sav'))
                     .
SORT CASES BY flow comno.                   
SAVE OUTFILE=!quote(!concat('data/tradedata_',!flow,'_',!year_1,'.sav')).
* Previous year.
GET FILE=!quote(!concat('Data/weight_base_',!flow,'_',!year_1,'.sav')).
AGGREGATE outfile=*
         /BREAK =flow comno section Weight_HS
         /num=N(flow).
DELETE VARIABLES num.
EXECUTE.

MATCH FILES FILE=!quote(!concat('data/tradedata_',!flow,'_',!year_1,'.sav'))
           /TABLE=*
           /in =From_base
           /by flow comno
           .

FREQUENCIES from_base.

* Previous year.
SELECT IF (from_base = 1 and year = !year_1).
EXECUTE.

FREQUENCIES transactionHS_under_limit.

COMPUTE price = value / uv_weight.
execute.

*REMOVE OUTLIERS TRANSACTION LEVEL WITHIN GROUP AND QUARTER - MAD

FREQUENCIES outlier_dev_median_q.

SELECT IF (outlier_dev_median_q = 0 OR outlier_dev_median_q = 2).
EXECUTE.

*REMOVE VARIABLES

*DETECT EXTREME PRICE CHANGE FOR TRANSACTIONS WITHIN BASEYEAR (DEVIATION FROM MEDIAN YEAR)

AGGREGATE
  /OUTFILE=* MODE=ADDVARIABLES
  /BREAK=flow comno 
  /price_median_year=MEDIAN(price)
  .

DO IF (price / price_median_year < !outlier_median_year_limit_lower).
 COMPUTE outlier_median_baseyear = 1.
ELSE IF (price / price_median_year > !outlier_median_year_limit_upper).
 COMPUTE outlier_median_baseyear = 2.
ELSE.
  COMPUTE outlier_median_baseyear = 0.
end if.

FREQUENCIES outlier_median_baseyear.


*TEMPORARY.
*SELECT IF (any(outlier_median_baseyear,1,2)).
*list flow comno outlier_median_baseyear.

SELECT IF (outlier_median_baseyear = 0).
EXECUTE.

*CALCULATE STANDARD DEVIATION FROM THE MEAN (YEAR Or QUARTER?)

AGGREGATE
  /OUTFILE=* MODE=ADDVARIABLES
  /BREAK=flow comno quarter 
  /sd_comno_base=SD(price)
  /mean_comno_base=MEAN(price).

* Mark outliers.
COMPUTE ul_base = mean_comno_base + (!outlier_sd_limit_upper * sd_comno_base).
COMPUTE ll_base = mean_comno_base - (!outlier_sd_limit_lower * sd_comno_base).
COMPUTE outlier_sd_base = 0.
IF (price < ll_base OR price > ul_base) outlier_sd_base = 1.


FREQUENCIES outlier_sd_base.
MEANS TABLES=value BY outlier_sd_base
  /CELLS=MEAN COUNT STDDEV SUM.

SELECT IF (outlier_sd_base = 0).
EXECUTE.

FREQUENCIES transactionHS_under_limit.

SELECT IF (transactionHS_under_limit = 0).
EXECUTE.

* Add no of transactions after removal.
AGGREGATE
  /OUTFILE=* MODE=ADDVARIABLES
  /BREAK=flow comno quarter 
  /no_trans_after_rm=N()
.

*AGGREGATE VALUE AND WEIGHT AND CALCULATE PRICE FOR COMNO-LEVEL

AGGREGATE /OUTFILE=*
          /BREAK=flow comno section Weight_HS Year quarter
          /value_quarter = SUM(value)
          /weight_quarter = SUM(uv_weight)
          .

COMPUTE price = value_quarter / weight_quarter.
EXECUTE.
FORMATS quarter (f8).

DELETE VARIABLES value_quarter weight_quarter year.

CASESTOVARS
  /ID=flow comno section Weight_HS 
  /INDEX= quarter 
  /SEPARATOR='_'
  /GROUPBY=VARIABLE.
EXECUTE.

* Compute price relative.
COMPUTE  price_rel_1 = price_4 / price_3.
COMPUTE  price_rel_2 = price_4 / price_2.

COMPUTE product_1 = price_rel_1 * Weight_HS.
COMPUTE product_2 = price_rel_2 * Weight_HS.
EXECUTE.


AGGREGATE /OUTFILE=* MODE=ADDVARIABLES
          /BREAK=flow section
          /prod_sum_1 = SUM(product_1)
          /prod_sum_2 = SUM(product_2)
          .

* aggregated weight for those who have valid values for price (and product).
COMPUTE Weight_section = Weight_HS * NOT(sysmis(product_1)).
EXECUTE.

AGGREGATE /OUTFILE=* MODE=ADDVARIABLES OVERWRITE=yes
          /BREAK=flow section
          /Weight_section = SUM(Weight_section)
          .

compute impute_base = sysmis(price_4).
do if (impute_base = 1).
   IF (sysmis(price_3) = 0) price_4 =  price_3 * prod_sum_1 /  Weight_section.
   IF  (sysmis(price_3) = 1)  price_4 =  price_2 * prod_sum_2 /  Weight_section.
end if.

FREQUENCIES impute_base.


AGGREGATE /OUTFILE=* MODE=ADDVARIABLES OVERWRITE=YES
          /BREAK=flow 
          /prod_sum_1 = SUM(product_1)
          /prod_sum_2 = SUM(product_2)
          .

* aggregated weight for those who have valid values for price (and product).
COMPUTE Weight_flow = Weight_HS * NOT(sysmis(product_1)).
EXECUTE.

AGGREGATE /OUTFILE=* MODE=ADDVARIABLES OVERWRITE=YES
          /BREAK=flow 
          /Weight_flow = SUM(Weight_flow)
          .

if (impute_base = 1) impute_base = sysmis(price_4) + 1 .
do if (impute_base = 2).
   IF (sysmis(price_3) = 0) price_4 =  price_3 * prod_sum_1 /  Weight_flow.
   IF  (sysmis(price_3) = 1)  price_4 =  price_2 * prod_sum_2 /  Weight_flow.
end if.

FREQUENCIES impute_base.

TITLE 'List of imputed commodities'.
TEMPORARY.
SELECT IF (any(impute_base,1,2)).
LIST ALL.

RENAME VARIABLES (price_4 = base_price) .


* Save for previous year.
SAVE OUTFILE=!quote(!concat('Data/base_price_',!flow,'_',!year_1,'.sav')) /KEEP flow comno base_price impute_base.


* Create an empty dataset for unchained indexes for actual year.
SELECT IF(flow = '7').
EXECUTE.
SAVE OUTFILE=!quote(!concat('Data/index_unchained_',!flow,'_',!year,'.sav')) /KEEP=flow.

!ENDDEFINE.