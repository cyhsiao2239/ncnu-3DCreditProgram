# 上線設定指南：Supabase + GitHub Pages

這份指南照著做一次即可，之後每學期只要重新「匯入名冊」，不需要重做這些步驟。

## 第一步：建立 Supabase 專案

1. 前往 https://supabase.com ，用 Email 或 GitHub 帳號註冊、登入。
2. 點「New project」，輸入專案名稱（例如 `ncnu-course-hub`），設定一組資料庫密碼（記下來，之後大概用不到但要保留）。
3. 地區選 **Southeast Asia (Singapore)** 延遲最低，等 1–2 分鐘讓專案建立完成。

## 第二步：建立資料表

1. 左側選單點 **SQL Editor** → **New query**。
2. 開啟本次一併提供的 `supabase_schema.sql`，全選複製，貼到編輯器。
3. 點右下角 **Run**。跑完應該顯示 Success，左側 **Table Editor** 會出現
   `terms`、`groups`、`students`、`evaluations`、`votes`、`course_settings`、
   `staff_members` 七張表。

## 第三步：建立老師／助教帳號

1. 左側選單 **Authentication** → **Users** → **Add user**。
2. 輸入要登入「教師專用」的 Email 與密碼（自訂，例如用學校信箱）。
3. 「Auto Confirm User」打勾（不用寄送驗證信）。建立後這組帳密就是「教材編輯區 / 課程資料匯入」的登入方式，**不是**寫死在程式碼裡，所以資安上安全很多。
4. **助教要一起編輯的話，重複這個步驟，用助教自己的 Email 再建一組帳號即可。** 老師跟助教各自用自己的帳密登入，權限完全一樣（都能匯入名冊、看自評與投票、刪除歷史資料），系統會自動同步、不會互相覆蓋——因為資料本來就存在同一個 Supabase 資料庫，不是各自本機的檔案。
5. 之後在「教材編輯區」右上角會顯示「目前登入：xxx@xxx.com」，方便確認現在是哪個帳號在操作。

> 之後要新增第三、第四位帳號（例如換學期、換助教），重複步驟 1–3 即可，不需要改程式碼。

教師／TA 登入時，畫面輸入的是名冊中的「登入帳號」：

- 教師：員工編號
- TA：自己的學號

這個登入帳號會在 `staff_members.login_id` 對應到 Supabase Authentication
的 Email；目前也相容直接將個別管理者的 `staff_members.course_id` 設為員工編號／學號。
密碼仍由 Supabase Authentication 驗證。Excel 中標示為教師／助教／admin
的資料列，請提供 `登入帳號`、`電子郵件信箱`、`姓名` 與 `身分` 欄位。

## 第四步：拿到金鑰，填進網站

1. 左側選單 **Settings** → **API**。
2. 複製 **Project URL**（長得像 `https://xxxx.supabase.co`）。
3. 複製 **anon public** 這組 key（一長串英數字，這是「前端可公開使用」的金鑰，不是密碼，可以放心放進前端程式碼）。
4. 將 `config.example.js` 複製成 `config.js`，再把 `config.js` 中的占位符換成你剛剛複製的值：

```js
const SUPABASE_URL = "YOUR_SUPABASE_URL";
const SUPABASE_ANON_KEY = "YOUR_SUPABASE_ANON_KEY";
```

`config.js` 已列入 `.gitignore`，請不要將它提交到版本控制；部署到 GitHub Pages 前，需在部署環境自行提供這個檔案。`config.example.js` 只保留占位符，可安全提交。

### 已建立過舊版資料庫時

如果你的 Supabase 已經執行過舊版 `supabase_schema.sql`，只需要執行
`MIGRATION_EXISTING_PROJECT.sql` 一次。這支檔案會一次完成：

- 允許學生先以「尚未分組」狀態匯入。
- 建立教師／助教管理名單 `staff_members`。
- 加入 `staff_members.login_id`，讓教師／TA 可使用員工編號／學號登入。
- 加入學年度與期中／期末切換欄位。
- 將舊版期別唯一鍵升級為「課程＋學年度＋期別」。

這支檔案可以安全重跑；若畫面顯示 constraint 已存在，不需要再執行其他 SQL。
匯入 Excel 中的 `admin` 資料會寫入 `staff_members`，但不會建立
Supabase Authentication 帳號；每位教師／助教仍須先在 Authentication → Users
建立相同 Email 的帳號，並在名冊或 `staff_members.login_id` 設定對應的員工編號／學號，
登入後即具有相同的管理權限。

如果教師後台顯示已有小組，但學生端的分組卡片沒有組員，請重新執行這支
整合 migration，讓 `get_group_roster` 查詢函式更新為目前版本。

### 學年度與期中／期末

執行升級檔後，教師後台的「新增學年度」只會建立空白的期中與期末期別，不會複製舊名單。
教師後台的「新增學年度」只會建立空白的期中與期末期別，不會複製舊名單。
對某學年度匯入一次名冊時，系統會同步更新該學年度的期中與期末名單。

## 第五步：本機測試

1. 直接用瀏覽器打開 `index.html`（雙擊或拖進瀏覽器視窗）。
2. 右上角「教師專用」→「課程資料匯入」→ 用第三步建立的 Email/密碼登入。
3. 選擇要匯入的學年度，上傳學生名冊 CSV/Excel；系統會同步更新該學年度的期中與期末
   （欄位：學號、姓名、系級、組別、身分）。
4. 匯入成功後，登出教師，重新整理頁面，用其中一位學生的學號＋姓名登入測試分組名單、自評、投票是否正常。

## 第六步：放到 GitHub Pages 讓全班連上線

1. 到 https://github.com ，建立一個新的 **Public** repository（例如 `ncnu-3DCreditProgram`）。
2. 把改好金鑰的 `index.html` 上傳到這個 repository 的根目錄（GitHub 網頁上有「Add file → Upload files」，直接拖拉上傳即可，不需要用指令）。
3. 進入 repository 的 **Settings** → 左側 **Pages**。
4. **Source** 選 `Deploy from a branch`，**Branch** 選 `main` / `(root)`，按 **Save**。
5. 等 1–2 分鐘，畫面上會出現一個網址，格式類似：
   `https://你的帳號.github.io/ncnu-3DCreditProgram/`
6. 這就是全班同學要連的網址，可以直接分享、做成 QR Code。

> 之後只要程式碼有更新，重新上傳覆蓋 `index.html` 即可，GitHub Pages 會自動重新部署。

## 重要提醒（請務必知道）

- **anon key 會出現在網站原始碼裡，這是正常且必要的**（Supabase 的設計本來就是前端直接用這組 key 呼叫資料庫），真正的保護是我們設定的資料庫規則（RLS）與驗證函式：學生只能透過受限制的函式讀寫「自己」的資料，看不到全班名冊；老師功能則需要 Supabase Auth 帳密才能使用。
- 因為學生登入只用「學號＋姓名」、沒有密碼，**理論上知道同學學號姓名的人可以冒名投票或填自評**——這是這次您選擇「簡單快速」登入方式的必然取捨。如果之後想加強，最簡單的做法是在 `students` 表加一個 `access_code`（例如學號後四碼）欄位，登入時多比對一個欄位即可，我可以之後協助加。
- Google Sheets Webhook 是「選用備份」，不是必要步驟，不設定也完全不影響系統運作。

### Google Sheets Webhook 測試

1. 開啟 Google 試算表 → **擴充功能 → Apps Script**。
2. 將 [GOOGLE_APPS_SCRIPT.gs](./GOOGLE_APPS_SCRIPT.gs) 的內容貼入 Apps Script。
3. 將 `SPREADSHEET_ID` 改成試算表網址 `/d/` 與 `/edit` 之間的文字，並確認工作表名稱為 `Responses`。
4. 點選 **部署 → 新增部署作業 → 網頁應用程式**：
   - 執行身分：我
   - 存取權：任何人
5. 複製結尾為 `/exec` 的網址，貼到網站「Google Apps Script Webhook」欄位並儲存。
6. 學生成功送出自評或投票後，資料會新增到 `Responses` 工作表。Supabase 仍是正式資料來源，試算表只作為備份與統計。
- 如果之後想要「即時看到別人剛剛投的票」而不用手動重新整理，可以再加 Supabase 的 Realtime 訂閱功能，屬於加分項，目前版本是「送出後重新查詢」，對課堂使用已經足夠。
