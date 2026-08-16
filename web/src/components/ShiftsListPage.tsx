// Placeholder so the /shifts route resolves. Shift definitions are still
// managed via the CLI (`shift create|list|delete`); the admin page is next.
export default function ShiftsListPage() {
  return (
    <div className="page">
      <h2>Shifts</h2>
      <p className="text-muted">
        Shift definitions are managed via the CLI for now.
      </p>
    </div>
  );
}
