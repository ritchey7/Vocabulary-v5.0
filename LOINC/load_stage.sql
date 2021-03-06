/*
1. Logon to https://loinc.org/downloads/loinc
Download full set (http://loinc.org/downloads/files/loinc-table-csv-text-format/loinc-table-file-csv-text-format/download). 
Also, download multiaxial hierarchy (http://loinc.org/downloads/files/loinc-multiaxial-hierarchy/loinc-multiaxial-hierarchy-file/download). 
In the box "Intended use" fill in "Incorporation into OMOP Standardized Vocabulary" 

Load LOINC Answers - Load LOINC_XXX_SELECTED_FORMS.zip from http://loinc.org/downloads/files/loinc-panels-and-forms-file/loinc-panels-and-forms-file-all-selected-panels-and-forms/download
Open LOINC_XXX_SELECTED_FORMS.xlsx and load worksheet "ANSWERS" to table LOINC_ANSWERS

2. DDL & ctl -> Vocabulary-v5.0\LOINC\

-- Update latest_update field to new date 
update vocabulary set latest_update=to_date('YYYYMMDD','yyyymmdd') where vocabulary_id='LOINC'; commit;
*/

--3. Create concept_stage from LOINC
INSERT INTO concept_stage (concept_id,
                           concept_name,
                           domain_id,
                           vocabulary_id,
                           concept_class_id,
                           standard_concept,
                           concept_code,
                           valid_start_date,
                           valid_end_date,
                           invalid_reason)
   SELECT NULL AS concept_id,
          CONSUMER_NAME AS concept_name,
          CASE CLASSTYPE
             WHEN '1' THEN 'Measurement'
             WHEN '2' THEN 'Measurement'
             WHEN '3' THEN 'Observation'
             WHEN '4' THEN 'Observation'
          END
             AS domain_id,
          v.vocabulary_id,
          CASE CLASSTYPE
             WHEN '1' THEN 'Lab Test'
             WHEN '2' THEN 'Clinical Observation'
             WHEN '3' THEN 'Claims attachment'
             WHEN '4' THEN 'Survey'
          END
             AS concept_class_id,
          'S' AS standard_concept,
          LOINC_NUM AS concept_code,
          CASE
             WHEN STATUS = 'ACTIVE' AND CHNG_TYPE = 'ADD'
             THEN
                COALESCE (DATE_LAST_CHANGED, v.latest_update)
             WHEN STATUS = 'TRIAL' AND CHNG_TYPE = 'ADD'
             THEN
                COALESCE (DATE_LAST_CHANGED, v.latest_update)
             ELSE
                v.latest_update
          END
             AS valid_start_date,
          CASE
             WHEN STATUS = 'DISCOURAGED' AND CHNG_TYPE = 'DEL'
             THEN
                DATE_LAST_CHANGED
             WHEN STATUS = 'DISCOURAGED'
             THEN
                v.latest_update
             WHEN STATUS = 'DEPRECATED'
             THEN
                DATE_LAST_CHANGED
             ELSE
                TO_DATE ('20991231', 'yyyymmdd')
          END
             AS valid_end_date,
          CASE
             WHEN EXISTS
                     (SELECT 1
                        FROM MAP_TO m
                       WHERE m.loinc = l.loinc_num)
             THEN
                'U'
             WHEN STATUS = 'DISCOURAGED'
             THEN
                'D'
             WHEN STATUS = 'DEPRECATED'
             THEN
                'D'
             ELSE
                NULL
          END
             AS invalid_reason
     FROM LOINC l, vocabulary v
    WHERE v.vocabulary_id = 'LOINC';
COMMIT;					  

--4 create classes from xlsx
create table concept_stage_LOINC_tmp as select * from concept_stage where 1=0;
--load data from xlsx, remove empty lines, then
insert into concept_stage select * From concept_stage_LOINC_tmp;
COMMIT;
DROP table concept_stage_LOINC_tmp purge;

--5 Add LOINC hierarchy
INSERT INTO concept_stage (concept_id,
                           concept_name,
                           domain_id,
                           vocabulary_id,
                           concept_class_id,
                           standard_concept,
                           concept_code,
                           valid_start_date,
                           valid_end_date,
                           invalid_reason)
   SELECT DISTINCT
          NULL AS concept_id,
          SUBSTR (code_text, 1, 256) AS concept_name,
          CASE WHEN CODE > 'LP76352-1' THEN 'Observation' ELSE 'Measurement' END
             AS domain_id,
          'LOINC' AS vocabulary_id,
          'LOINC Hierarchy' AS concept_class_id,
          'C' AS standart_concept,
          CODE AS concept_code,
          TO_DATE ('19700101', 'yyyymmdd') AS valid_start_date,
          TO_DATE ('20991231', 'yyyymmdd') AS valid_end_date,
          NULL AS invalid_reason
     FROM loinc_hierarchy
    WHERE CODE LIKE 'LP%';
COMMIT;

--6 Add concept_relationship_stage link to multiaxial hierarchy
INSERT INTO concept_relationship_stage (concept_id_1,
                                        concept_id_2,
                                        concept_code_1,
                                        concept_code_2,
                                        relationship_id,
                                        vocabulary_id_1,
                                        vocabulary_id_2,
                                        valid_start_date,
                                        valid_end_date,
                                        invalid_reason)
   SELECT DISTINCT NULL AS concept_id_1,
          NULL AS concept_id_2,
          IMMEDIATE_PARENT AS concept_code_1,
          CODE AS concept_code_2,
          'Subsumes' AS relationship_id,
          'LOINC' AS vocabulary_id_1,
          'LOINC' AS vocabulary_id_2,
          TO_DATE ('19700101', 'yyyymmdd') AS valid_start_date,
          TO_DATE ('31.12.2099', 'dd.mm.yyyy') AS valid_end_date,
          NULL AS invalid_reason
     FROM LOINC_HIERARCHY;
COMMIT;

--7 Add concept_relationship_stage to LOINC Classes inside the Class table. Create a 'Subsumes' relationship
INSERT INTO concept_relationship_stage (concept_id_1,
                                        concept_id_2,
                                        concept_code_1,
                                        concept_code_2,
                                        relationship_id,
                                        vocabulary_id_1,
                                        vocabulary_id_2,
                                        valid_start_date,
                                        valid_end_date,
                                        invalid_reason)
   SELECT DISTINCT NULL AS concept_id_1,
          NULL AS concept_id_2,
          l2.concept_code AS concept_code_1,
          l1.concept_code AS concept_code_2,
          'Subsumes' AS relationship_id,
          'LOINC' AS vocabulary_id_1,
          'LOINC' AS vocabulary_id_2,
          TO_DATE ('19700101', 'yyyymmdd') AS valid_start_date,
          TO_DATE ('31.12.2099', 'dd.mm.yyyy') AS valid_end_date,
          NULL AS invalid_reason
     FROM concept_stage_LOINC_tmp l1, concept_stage_LOINC_tmp l2
    WHERE     l1.concept_code LIKE l2.concept_code || '%'
          AND l1.concept_code <> l2.concept_code;
COMMIT;

--8 Add concept_relationship between LOINC and LOINC classes from LOINC
INSERT INTO concept_relationship_stage (concept_id_1,
                                        concept_id_2,
                                        concept_code_1,
                                        concept_code_2,
                                        relationship_id,
                                        vocabulary_id_1,
                                        vocabulary_id_2,
                                        valid_start_date,
                                        valid_end_date,
                                        invalid_reason)
   SELECT NULL AS concept_id_1,
          NULL AS concept_id_2,
          l.class AS concept_code_1,
          l.loinc_num AS concept_code_2,
          'Subsumes' AS relationship_id,
          'LOINC' AS vocabulary_id_1,
          'LOINC' AS vocabulary_id_2,
          TO_DATE ('19700101', 'yyyymmdd') AS valid_start_date,
          TO_DATE ('31.12.2099', 'dd.mm.yyyy') AS valid_end_date,
          NULL AS invalid_reason
     FROM concept_stage_LOINC_tmp lc, loinc l
    WHERE lc.concept_code = l.class;
COMMIT;
	
--9 Create CONCEPT_SYNONYM_STAGE
INSERT INTO concept_synonym_stage (synonym_concept_id,
                                   synonym_concept_code,
                                   synonym_name,
                                   language_concept_id)
   (SELECT NULL AS synonym_concept_id,
           LOINC_NUM AS synonym_concept_code,
           SUBSTR (TO_CHAR (RELATEDNAMES2), 1, 1000) AS synonym_name,
           4093769 AS language_concept_id                           -- English
      FROM loinc
     WHERE TO_CHAR (RELATEDNAMES2) IS NOT NULL
    UNION
    SELECT NULL AS synonym_concept_id,
           LOINC_NUM AS synonym_concept_code,
           SUBSTR (LONG_COMMON_NAME, 1, 1000) AS synonym_name,
           4093769 AS language_concept_id                           -- English
      FROM loinc
     WHERE LONG_COMMON_NAME IS NOT NULL
    UNION
    SELECT NULL AS synonym_concept_id,
           LOINC_NUM AS synonym_concept_code,
           SHORTNAME AS synonym_name,
           4093769 AS language_concept_id                           -- English
      FROM loinc
     WHERE SHORTNAME IS NOT NULL);
COMMIT;

--10 Add more Loinc concepts and relationships
INSERT INTO concept_stage (concept_id,
                           concept_name,
                           domain_id,
                           vocabulary_id,
                           concept_class_id,
                           standard_concept,
                           concept_code,
                           valid_start_date,
                           valid_end_date,
                           invalid_reason)
   SELECT DISTINCT
          NULL AS concept_id,
          DisplayText AS concept_name,
          CASE CLASSTYPE
             WHEN '1' THEN 'Measurement'
             WHEN '2' THEN 'Measurement'
             WHEN '3' THEN 'Observation'
             WHEN '4' THEN 'Observation'
          END
             AS domain_id,
          'LOINC' AS vocabulary_id,
          'LOINC Answer' AS concept_class_id,
          'S' AS standard_concept,
          AnswerStringID AS concept_code,
          TO_DATE ('19700101', 'yyyymmdd') AS valid_start_date,
          TO_DATE ('20991231', 'yyyymmdd') AS valid_end_date,
          NULL AS invalid_reason
     FROM LOINC_ANSWERS la, loinc l
    WHERE la.loinc = l.loinc_num AND AnswerStringID IS NOT NULL; --AnswerStringID may be null
COMMIT;	

--11 Link LOINCs to Answers in concept_relationship_stage
INSERT INTO concept_relationship_stage (concept_id_1,
                                        concept_id_2,
                                        concept_code_1,
                                        concept_code_2,
                                        relationship_id,
                                        vocabulary_id_1,
                                        vocabulary_id_2,
                                        valid_start_date,
                                        valid_end_date,
                                        invalid_reason)
   SELECT DISTINCT NULL AS concept_id_1,
                   NULL AS concept_id_2,
                   Loinc AS concept_code_1,
                   AnswerStringID AS concept_code_2,
                   'Has Answer' AS relationship_id,
                   'LOINC' AS vocabulary_id_1,
                   'LOINC' AS vocabulary_id_2,
                   TO_DATE ('19700101', 'yyyymmdd') AS valid_start_date,
                   TO_DATE ('20991231', 'yyyymmdd') AS valid_end_date,
                   NULL AS invalid_reason
     FROM LOINC_ANSWERS
    WHERE AnswerStringID IS NOT NULL;
COMMIT;	

--12------ run Vocabulary-v5.0\generic_update.sql ---------------			