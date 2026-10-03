-- ============================================================================
-- 既有 Supabase 專案升級檔
-- 用途：已經執行過舊版 supabase_schema.sql 的專案。
-- 可重複執行。新專案請改執行 supabase_schema.sql，不要執行本檔。
-- ============================================================================

-- 1. 允許名冊先匯入、之後再補上組別。
alter table students alter column group_no drop not null;

-- 尚未分組的學生不可自評。
create or replace function submit_evaluation(
  p_term_id uuid, p_evaluator_id text, p_scores jsonb, p_feedback text
) returns void language plpgsql security definer as $$
declare
  v_group int;
  v_key text;
  v_val int;
begin
  select group_no into v_group from students
  where term_id = p_term_id and student_id = p_evaluator_id;

  if not exists (
    select 1 from students where term_id = p_term_id and student_id = p_evaluator_id
  ) then
    raise exception '找不到這位學生';
  end if;
  if v_group is null then
    raise exception '尚未完成分組，暫時無法進行小組自評';
  end if;

  for v_key, v_val in select key, value::int from jsonb_each_text(p_scores) loop
    if v_val < 0 or v_val > 10 then
      raise exception '分數必須介於 0 到 10';
    end if;
    if not exists (
      select 1 from students
      where term_id = p_term_id and student_id = v_key and group_no = v_group
    ) then
      raise exception '評分對象不屬於同一組';
    end if;
  end loop;

  insert into evaluations (term_id, evaluator_id, scores, feedback, submitted_at, updated_at)
  values (p_term_id, p_evaluator_id, p_scores, coalesce(p_feedback,''), now(), now())
  on conflict (term_id, evaluator_id)
  do update set scores = excluded.scores, feedback = excluded.feedback, updated_at = now();
end;
$$;

-- 尚未分組的學生不可投票。
create or replace function submit_vote(
  p_term_id uuid, p_student_id text, p_groups int[], p_feedback text
) returns void language plpgsql security definer as $$
begin
  if array_length(p_groups,1) is distinct from 2 then
    raise exception '請選擇恰好 2 個組別';
  end if;
  if p_groups[1] = p_groups[2] then
    raise exception '不能重複選擇同一組';
  end if;
  if not exists (
    select 1 from students where term_id = p_term_id and student_id = p_student_id
  ) then
    raise exception '找不到這位學生';
  end if;
  if exists (
    select 1 from students
    where term_id = p_term_id and student_id = p_student_id and group_no is null
  ) then
    raise exception '尚未完成分組，暫時無法進行分組投票';
  end if;

  insert into votes (term_id, student_id, selected_groups, feedback, submitted_at, updated_at)
  values (p_term_id, p_student_id, p_groups, coalesce(p_feedback,''), now(), now())
  on conflict (term_id, student_id)
  do update set selected_groups = excluded.selected_groups, feedback = excluded.feedback, updated_at = now();
end;
$$;

-- 2. 保存 Excel 中的教師／助教管理名單。
create table if not exists staff_members (
  id uuid primary key default gen_random_uuid(),
  course_id text not null,
  email text not null,
  name text not null default '',
  role text not null default 'admin' check (role = 'admin'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (course_id, email)
);

alter table staff_members enable row level security;
drop policy if exists "teacher manage staff_members" on staff_members;
create policy "teacher manage staff_members" on staff_members for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

-- 確保查看分組名單會從目前期別的 students 回傳組員。
create or replace function get_group_roster(p_term_id uuid)
returns table (group_no int, name text, topic text, member_name text)
language sql security definer
set search_path = public
as $$
  select g.group_no, g.name, g.topic, s.name as member_name
  from groups g
  left join students s
    on s.term_id = g.term_id
   and s.group_no = g.group_no
  where g.term_id = p_term_id
  order by g.group_no, s.name;
$$;

grant execute on function get_group_roster(uuid) to anon, authenticated;

-- 以每組一列、組員陣列的形式提供前端，避免舊 RPC／schema cache 遺留問題。
create or replace function get_public_group_roster(p_term_id uuid)
returns table (group_no int, name text, topic text, members text[])
language sql security definer
set search_path = public
as $$
  select
    g.group_no,
    g.name,
    g.topic,
    coalesce(
      array_agg(s.name order by s.name) filter (where s.name is not null),
      '{}'::text[]
    ) as members
  from groups g
  left join students s
    on s.term_id = g.term_id
   and s.group_no = g.group_no
  where g.term_id = p_term_id
  group by g.group_no, g.name, g.topic
  order by g.group_no;
$$;

grant execute on function get_public_group_roster(uuid) to anon, authenticated;

-- 3. 加入學年度，並保留既有資料的舊學年度標記。
alter table terms add column if not exists academic_year text;
update terms
set academic_year = case
  when course_id = '1142_CCI' then '1142'
  else coalesce(academic_year, '1151')
end
where academic_year is null;
alter table terms alter column academic_year set default '1151';
alter table terms alter column academic_year set not null;

alter table course_settings add column if not exists active_academic_year text;
update course_settings
set active_academic_year = case
  when course_id = '1142_CCI' then '1142'
  else coalesce(active_academic_year, '1151')
end
where active_academic_year is null;
alter table course_settings alter column active_academic_year set default '1151';
alter table course_settings alter column active_academic_year set not null;

-- 目前使用 1151 學年度；舊 course_id 只作為資料庫識別碼，不再顯示 1142。
update terms
set course_name = '文化創意產業'
where course_id = '1142_CCI' and academic_year = '1151';

-- 舊版唯一鍵只限制 course_id + term_key，會阻擋不同學年度並存。
-- 同時移除兩種可能已存在的名稱，避免重跑時出現 constraint already exists。
alter table terms drop constraint if exists terms_course_id_term_key_key;
alter table terms drop constraint if exists terms_course_year_term_key_key;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'terms'::regclass
      and conname = 'terms_course_year_term_key_key'
  ) then
    alter table terms
      add constraint terms_course_year_term_key_key
      unique (course_id, academic_year, term_key);
  end if;
end
$$;
