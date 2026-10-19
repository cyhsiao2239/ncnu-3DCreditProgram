# 文創課程活動中控台

這是一個以 Supabase 與單一 HTML 前端建立的課程活動管理系統，提供學生查看分組、進行小組自評、分組投票，以及查看成果報告；教師與助教可以匯入名冊、管理分組、檢視評量結果並下載 Word 成果報告。

目前預設課程為「文化創意產業」，也支援在管理員中控台新增及切換不同課程。每門課程的學年度、期中／期末、名冊、分組、自評、投票與成果報告資料彼此獨立。

## 功能

- 學生登入：選擇課程後，以學號與姓名登入。
- 查看分組名單與小組主題。
- 小組自評：對同組成員評分並留下回饋。
- 分組投票：每人選擇兩個組別，可修改投票與回饋。
- 成果報告：顯示匿名回饋與投票排名。
- 管理員中控台：
  - 新增及切換課程。
  - 設定學年度與目前開放的期中／期末。
  - 匯入 CSV／Excel 學生名冊。
  - 管理小組主題與分組。
  - 檢視自評、投票與完成狀態。
  - 清除測試用主題、自評或投票資料。
  - 下載 Word 格式成果報告。

## 專案檔案

| 檔案 | 用途 |
| --- | --- |
| `index.html` | 應用程式前端 |
| `config.example.js` | Supabase 設定範例 |
| `supabase_schema.sql` | 新專案建立完整資料庫結構 |
| `MIGRATION_EXISTING_PROJECT.sql` | 已有舊版資料庫時的升級檔 |
| `SETUP_GUIDE.md` | Supabase、帳號與 GitHub Pages 的完整設定說明 |

## 快速開始

### 1. 設定 Supabase

新專案請在 Supabase SQL Editor 執行：

```text
supabase_schema.sql
```

如果資料庫已經有「文化創意產業」課程名冊與活動資料，請執行：

```text
MIGRATION_EXISTING_PROJECT.sql
```

此 migration 使用可重複執行的設定，不會刪除既有名冊、分組、自評或投票資料。執行前仍建議先確認 Supabase 備份正常。

### 2. 設定前端金鑰

複製設定範例：

```powershell
Copy-Item config.example.js config.js
```

編輯 `config.js`，填入 Supabase Project URL 與 anon public key：

```js
const SUPABASE_URL = "YOUR_SUPABASE_URL";
const SUPABASE_ANON_KEY = "YOUR_SUPABASE_ANON_KEY";
```

`config.js` 已列入 `.gitignore`，不要提交真實金鑰以外的敏感資訊或服務金鑰。

### 3. 建立教師／助教帳號

在 Supabase **Authentication → Users** 建立教師或助教帳號並設定密碼。教師登入對應的登入帳號與 Email，可透過匯入名冊中的管理者資料寫入 `staff_members`。

### 4. 啟動網站

這是無建置步驟的靜態網站。可以直接開啟 `index.html`，或部署到 GitHub Pages。

部署後：

1. 進入「教師專用」。
2. 使用「課程資料匯入」登入。
3. 匯入學生名冊。
4. 在管理員中控台新增或切換課程。
5. 分別為各門課程匯入對應名冊。

## 新增課程

教師登入管理員中控台後，在「課程與評量階段」區塊按下「新增課程」，輸入：

- 課程代碼：只能使用英文字母、數字與底線，例如 `COURSE_1152_A`
- 課程名稱
- 預設學年度，例如 `1152`

系統會建立該課程的期中與期末期別。之後從「目前課程」切換課程，再到「課程資料匯入」匯入該課程名冊。

也可以先在 Supabase SQL Editor 建立課程：

```sql
insert into courses (course_id, course_name)
values
  ('COURSE_1152_A', '第一門課程'),
  ('COURSE_1152_B', '第二門課程')
on conflict (course_id)
do update set course_name = excluded.course_name;
```

## 名冊欄位

學生資料至少需要：

- 學號
- 姓名
- 系級
- 組別（可先留空）

可使用中文欄位，也支援 `studentId`、`name`、`dept`、`groupId` 等英文欄位。教師／助教資料需另外提供身分、登入帳號與電子郵件。

## 安全注意事項

- 前端使用 Supabase anon key 是正常的；資料保護依賴 Supabase RLS 與限制用途的 RPC 函式。
- 不要把 Supabase service role key、密碼或其他私密金鑰放進前端或提交到 Git。
- 學生目前以學號與姓名登入，適合課堂活動的簡易流程；若需要更高安全性，應再加入存取碼或其他驗證方式。
- 詳細設定、資料庫升級與部署說明請參考 [SETUP_GUIDE.md](./SETUP_GUIDE.md)。

## 授權

本專案目前未另行指定開源授權；如需公開重用，請先確認專案維護者的授權安排。
