-- 清除 1151 學年度期中／期末的自評與投票結果。
-- 只會刪除 evaluations 與 votes，不會刪除學生、分組或小組主題。
-- 請確認目前確實要清除 1151 兩個期別的全部結果後再執行。

begin;

delete from evaluations
where term_id in (
  select id from terms
  where course_id = '1142_CCI'
    and academic_year = '1151'
    and term_key in ('midterm', 'final')
);

delete from votes
where term_id in (
  select id from terms
  where course_id = '1142_CCI'
    and academic_year = '1151'
    and term_key in ('midterm', 'final')
);

commit;

-- 驗證：下面四個數字都應該是 0。
select
  t.academic_year,
  t.term_key,
  (select count(*) from evaluations e where e.term_id = t.id) as evaluation_count,
  (select count(*) from votes v where v.term_id = t.id) as vote_count
from terms t
where t.course_id = '1142_CCI'
  and t.academic_year = '1151'
  and t.term_key in ('midterm', 'final')
order by t.term_key;
