const SPREADSHEET_ID = "YOUR_SPREADSHEET_ID";
const SHEET_NAME = "Responses";

function doPost(e) {
  try {
    const payload = JSON.parse(e.postData.contents || "{}");
    const sheet = SpreadsheetApp.openById(SPREADSHEET_ID).getSheetByName(SHEET_NAME);
    if (!sheet) throw new Error("找不到工作表：" + SHEET_NAME);

    if (sheet.getLastRow() === 0) {
      sheet.appendRow([
        "received_at",
        "type",
        "academic_year",
        "term_key",
        "student_id",
        "student_name",
        "scores",
        "selected_groups",
        "feedback"
      ]);
    }

    sheet.appendRow([
      new Date(),
      payload.type || "",
      payload.academic_year || "",
      payload.term_key || "",
      payload.student_id || "",
      payload.student_name || "",
      payload.scores ? JSON.stringify(payload.scores) : "",
      payload.selected_groups ? payload.selected_groups.join(",") : "",
      payload.feedback || ""
    ]);

    return ContentService
      .createTextOutput(JSON.stringify({ ok: true }))
      .setMimeType(ContentService.MimeType.JSON);
  } catch (error) {
    return ContentService
      .createTextOutput(JSON.stringify({ ok: false, error: String(error) }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}
