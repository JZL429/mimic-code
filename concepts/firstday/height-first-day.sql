-- This query extracts heights for adult ICU patients.
-- It uses all information from the patient's first ICU day.
-- This is done for consistency with other queries - it's not necessarily needed.
-- Height is unlikely to change throughout a patient's stay.

-- ** Requires the echodata view, generated by etc/echo-data.sql

DROP MATERIALIZED VIEW IF EXISTS heightfirstday CASCADE;
CREATE MATERIALIZED VIEW heightfirstday as
-- staging table to ensure all heights are in centimeters
with ce0 as
(
    SELECT
      c.icustay_id
      , case
        -- convert inches to centimetres
          when itemid in (920, 1394, 4187, 3486)
              then valuenum * 2.54
            else valuenum
        end as Height
    FROM chartevents c
    inner join icustays ie
        on c.icustay_id = ie.icustay_id
        and c.charttime <= ie.intime + interval '1' day
        and c.charttime > ie.intime - interval '1' day -- some fuzziness for admit time
    WHERE c.valuenum IS NOT NULL
    AND c.itemid in (226730,920, 1394, 4187, 3486,3485,4188) -- height
    AND c.valuenum != 0
    -- exclude rows marked as error
    AND c.error IS DISTINCT FROM 1
)
, ce as
(
    SELECT
        icustay_id
        -- extract the median height from the chart to add robustness against outliers
        , percentile_cont(0.5) WITHIN GROUP (ORDER BY height) as Height_chart
    from ce0
    where height > 100
    group by icustay_id
)
-- requires the echo-data.sql query to run
-- this adds heights from the free-text echo notes
, echo as
(
    select
        ec.subject_id
        -- all echo heights are in inches
        , 2.54*percentile_cont(0.5) WITHIN GROUP (ORDER BY height) as Height_Echo
    from echodata ec
    inner join icustays ie
        on ec.subject_id = ie.subject_id
        and ec.charttime < ie.intime + interval '1' day
    where height is not null
    and height*2.54 > 100
    group by ec.subject_id
)
select
    ie.icustay_id
    , coalesce(ce.Height_chart, ec.Height_Echo) as Height

    -- components
    , ce.Height_chart
    , ec.Height_echo
from icustays ie

-- filter to only adults
inner join patients pat
    on ie.subject_id = pat.subject_id
    and ie.intime > pat.dob + interval '1' year

left join ce
    on ie.icustay_id = ce.icustay_id

left join echo ec
    on ie.subject_id = ec.subject_id;