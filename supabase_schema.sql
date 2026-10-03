-- ============================================================================
-- 文化創意產業 課程活動中控台 - Supabase 資料庫結構
-- 使用方式：到 Supabase 專案 → SQL Editor → 貼上整份文件 → Run
-- ============================================================================

create extension if not exists pgcrypto;

-- ----------------------------------------------------------------------------
-- 1. 課程期別（一個 term = 某課程的某個學期＋期中或期末）
-- ----------------------------------------------------------------------------
create table if not exists terms (
  id uuid primary key default gen_random_uuid(),
  course_id text not null,
  academic_year text not null default '1151',
  course_name text not null,
  term_key text not null check (term_key in ('midterm','final')),
  created_at timestamptz not null default now(),
  unique (course_id, academic_year, term_key)
);

-- ----------------------------------------------------------------------------
-- 2. 小組（含報告主題，組員自行可編輯）
-- ----------------------------------------------------------------------------
create table if not exists groups (
  id uuid primary key default gen_random_uuid(),
  term_id uuid not null references terms(id) on delete cascade,
  group_no int not null,
  name text not null,
  topic text not null default '尚未設定小組主題',
  topic_updated_at timestamptz,
  unique (term_id, group_no)
);

-- ----------------------------------------------------------------------------
-- 3. 學生名冊
-- ----------------------------------------------------------------------------
create table if not exists students (
  id uuid primary key default gen_random_uuid(),
  term_id uuid not null references terms(id) on delete cascade,
  student_id text not null,
  name text not null,
  dept text not null default '',
  group_no int,
  unique (term_id, student_id)
);

-- 若資料表已建立過，允許先匯入尚未分組的課程參與者。
alter table students alter column group_no drop not null;

-- ----------------------------------------------------------------------------
-- 4. 小組自評（每位學生一筆，內含對每位組員的評分 jsonb）
--    scores 格式： {"1101": 8, "1102": 10}
-- ----------------------------------------------------------------------------
create table if not exists evaluations (
  id uuid primary key default gen_random_uuid(),
  term_id uuid not null references terms(id) on delete cascade,
  evaluator_id text not null,
  scores jsonb not null,
  feedback text not null default '',
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (term_id, evaluator_id)
);

-- ----------------------------------------------------------------------------
-- 5. 分組投票（每位學生一筆，可修改）
-- ----------------------------------------------------------------------------
create table if not exists votes (
  id uuid primary key default gen_random_uuid(),
  term_id uuid not null references terms(id) on delete cascade,
  student_id text not null,
  selected_groups int[] not null,
  feedback text not null default '',
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (term_id, student_id)
);

-- ----------------------------------------------------------------------------
-- 6. 課程設定：目前「開放給學生使用」的是期中還是期末
-- ----------------------------------------------------------------------------
create table if not exists course_settings (
  course_id text primary key,
  active_academic_year text not null default '1151',
  active_term_key text not null default 'midterm' check (active_term_key in ('midterm','final')),
  updated_at timestamptz not null default now()
);

-- 教師／助教名單：登入帳號仍由 Supabase Authentication 管理，
-- 此表用來保存課程內的管理角色與顯示資訊。
create table if not exists staff_members (
  id uuid primary key default gen_random_uuid(),
  course_id text not null,
  login_id text not null,
  email text not null,
  name text not null default '',
  role text not null default 'admin' check (role = 'admin'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (course_id, email),
  unique (course_id, login_id)
);

-- ============================================================================
-- Row Level Security
-- ============================================================================
alter table terms enable row level security;
alter table groups enable row level security;
alter table students enable row level security;
alter table evaluations enable row level security;
alter table votes enable row level security;
alter table course_settings enable row level security;
alter table staff_members enable row level security;

-- 任何人（含匿名前端）都能讀取「期別」與「小組」清單（公開資訊，不含個資）
create policy "public read terms" on terms for select using (true);
create policy "public read groups" on groups for select using (true);

-- 學生名冊、自評、投票內容「不」開放給 anon 直接 select，
-- 一律透過下方 RPC 函式（security definer）存取，避免整份名冊被撈走。
create policy "teacher manage terms" on terms for all
  using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "teacher manage groups" on groups for all
  using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "teacher manage students" on students for all
  using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "teacher read evaluations" on evaluations for select
  using (auth.role() = 'authenticated');
create policy "teacher read votes" on votes for select
  using (auth.role() = 'authenticated');

create policy "public read course_settings" on course_settings for select using (true);
create policy "teacher manage course_settings" on course_settings for all
  using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "teacher manage staff_members" on staff_members for all
  using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

-- 以教師／TA 編號查找對應的 Supabase Auth Email；密碼仍由 Auth 驗證。
create or replace function resolve_staff_login(p_login_id text)
returns table (email text)
language sql security definer
set search_path = public
as $$
  select s.email
  from staff_members s
  where lower(s.login_id) = lower(trim(p_login_id))
    and s.course_id = '1142_CCI'
  limit 1;
$$;

grant execute on function resolve_staff_login(text) to anon, authenticated;

-- ============================================================================
-- RPC 函式（security definer：以擁有者權限執行，繞過上面 RLS 的讀取限制，
-- 但函式內部自己做格式與範圍檢查，是學生端唯一合法的寫入/查詢入口）
-- ============================================================================

-- 登入驗證：用學號＋姓名比對名冊，成功回傳學生資料
create or replace function login_check(p_term_id uuid, p_student_id text, p_name text)
returns table (student_id text, name text, dept text, group_no int)
language sql security definer as $$
  select s.student_id, s.name, s.dept, s.group_no
  from students s
  where s.term_id = p_term_id
    and s.student_id = trim(p_student_id)
    and s.name = trim(p_name)
  limit 1;
$$;

-- 取得某期別的分組名單（含組員姓名，前端「查看分組名單」使用）
create or replace function get_group_roster(p_term_id uuid)
returns table (group_no int, name text, topic text, member_name text)
language sql security definer
set search_path = public
as $$
  select g.group_no, g.name, g.topic, s.name as member_name
  from groups g
  left join students s on s.term_id = g.term_id and s.group_no = g.group_no
  where g.term_id = p_term_id
  order by g.group_no, s.name;
$$;

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

-- 取得「自己那一組」的組員學號＋姓名（僅限同組，不會外洩全班名冊）
create or replace function get_my_group_members(p_term_id uuid, p_student_id text)
returns table (student_id text, name text, dept text)
language sql security definer as $$
  select s.student_id, s.name, s.dept
  from students s
  where s.term_id = p_term_id
    and s.group_no = (select group_no from students where term_id = p_term_id and student_id = p_student_id)
  order by s.name;
$$;

-- 小組自評送出／更新：先驗證評分者存在、每個評分對象都是同組同學、分數在 0~10
create or replace function submit_evaluation(
  p_term_id uuid, p_evaluator_id text, p_scores jsonb, p_feedback text
) returns void language plpgsql security definer as $$
declare
  v_group int;
  v_key text;
  v_val int;
begin
  select group_no into v_group from students where term_id = p_term_id and student_id = p_evaluator_id;
  if not exists (select 1 from students where term_id = p_term_id and student_id = p_evaluator_id) then
    raise exception '找不到這位學生';
  end if;
  if v_group is null then raise exception '尚未完成分組，暫時無法進行小組自評'; end if;

  for v_key, v_val in select key, value::int from jsonb_each_text(p_scores) loop
    if v_val < 0 or v_val > 10 then raise exception '分數必須介於 0 到 10'; end if;
    if not exists (select 1 from students where term_id = p_term_id and student_id = v_key and group_no = v_group) then
      raise exception '評分對象不屬於同一組';
    end if;
  end loop;

  insert into evaluations (term_id, evaluator_id, scores, feedback, submitted_at, updated_at)
  values (p_term_id, p_evaluator_id, p_scores, coalesce(p_feedback,''), now(), now())
  on conflict (term_id, evaluator_id)
  do update set scores = excluded.scores, feedback = excluded.feedback, updated_at = now();
end;
$$;

-- 學生查看「自己」是否已送出自評與內容（不會回傳其他人的資料）
create or replace function get_my_evaluation(p_term_id uuid, p_student_id text)
returns table (scores jsonb, feedback text, submitted_at timestamptz)
language sql security definer as $$
  select e.scores, e.feedback, e.submitted_at from evaluations e
  where e.term_id = p_term_id and e.evaluator_id = p_student_id;
$$;

-- 投票送出／修改：恰好兩組、不得重複、（依課程規則可投自己）
create or replace function submit_vote(
  p_term_id uuid, p_student_id text, p_groups int[], p_feedback text
) returns void language plpgsql security definer as $$
begin
  if array_length(p_groups,1) is distinct from 2 then raise exception '請選擇恰好 2 個組別'; end if;
  if p_groups[1] = p_groups[2] then raise exception '不能重複選擇同一組'; end if;
  if not exists (select 1 from students where term_id = p_term_id and student_id = p_student_id) then
    raise exception '找不到這位學生';
  end if;
  if exists (select 1 from students where term_id = p_term_id and student_id = p_student_id and group_no is null) then
    raise exception '尚未完成分組，暫時無法進行分組投票';
  end if;

  insert into votes (term_id, student_id, selected_groups, feedback, submitted_at, updated_at)
  values (p_term_id, p_student_id, p_groups, coalesce(p_feedback,''), now(), now())
  on conflict (term_id, student_id)
  do update set selected_groups = excluded.selected_groups, feedback = excluded.feedback, updated_at = now();
end;
$$;

-- 學生查看自己的投票狀態
create or replace function get_my_vote(p_term_id uuid, p_student_id text)
returns table (selected_groups int[], feedback text, submitted_at timestamptz, updated_at timestamptz)
language sql security definer as $$
  select v.selected_groups, v.feedback, v.submitted_at, v.updated_at from votes v
  where v.term_id = p_term_id and v.student_id = p_student_id;
$$;

-- 各組得票數（公開，給成果報告用）
create or replace function get_vote_totals(p_term_id uuid)
returns table (group_no int, votes bigint)
language sql security definer as $$
  select g.group_no, coalesce(count(v.id) filter (where g.group_no = any(v.selected_groups)), 0) as votes
  from groups g
  left join votes v on v.term_id = g.term_id
  where g.term_id = p_term_id
  group by g.group_no
  order by votes desc, g.group_no;
$$;

-- 匿名投票回饋（公開，不含姓名／學號／組別）
create or replace function get_anonymous_vote_feedback(p_term_id uuid)
returns table (feedback text)
language sql security definer as $$
  select v.feedback from votes v
  where v.term_id = p_term_id and coalesce(trim(v.feedback), '') <> ''
  order by v.updated_at desc;
$$;

-- 組員編輯自己小組的報告主題：驗證該學生確實屬於這一組
create or replace function update_group_topic(
  p_term_id uuid, p_group_no int, p_student_id text, p_topic text
) returns void language plpgsql security definer as $$
begin
  if not exists (
    select 1 from students
    where term_id = p_term_id and student_id = p_student_id and group_no = p_group_no
  ) then
    raise exception '只有本組同學可以修改報告主題';
  end if;
  if trim(p_topic) = '' then raise exception '報告主題不可為空白'; end if;

  update groups set topic = trim(p_topic), topic_updated_at = now()
  where term_id = p_term_id and group_no = p_group_no;
end;
$$;

-- ============================================================================
-- 執行權限：anon（前端未登入 Supabase Auth 的訪客）可以呼叫上面這些函式
-- ============================================================================
grant execute on function login_check, get_group_roster, get_my_group_members, submit_evaluation, get_my_evaluation,
  submit_vote, get_my_vote, get_vote_totals, get_anonymous_vote_feedback, update_group_topic,
  get_public_group_roster
  to anon, authenticated;

-- ============================================================================
-- 使用說明
-- 1. 這份 SQL 建好結構後，資料表本身是空的，需要老師登入後透過
--    「課程資料匯入」頁面上傳 CSV/Excel 名冊，系統會自動建立 term + groups + students。
-- 2. 老師帳號要另外到 Supabase 後台 Authentication → Users → Add user 建立
--    （建議用學校 Email + 自訂密碼），前端會用這組帳密登入教師專用區。
-- ============================================================================
