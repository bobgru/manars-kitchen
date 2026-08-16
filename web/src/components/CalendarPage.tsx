// Placeholder so the /calendar route resolves. The committed calendar is still
// viewed via the CLI (`calendar view`, `calendar history`); the admin page is
// next.
export default function CalendarPage() {
  return (
    <div className="page">
      <h2>Calendar</h2>
      <p className="text-muted">
        The committed calendar is viewed via the CLI for now.
      </p>
    </div>
  );
}
