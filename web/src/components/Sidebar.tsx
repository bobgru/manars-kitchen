import { NavLink } from "react-router";

const navItems = [
  { to: "/", label: "Dashboard", end: true },
  { to: "/skills", label: "Skills" },
  { to: "/stations", label: "Stations" },
  { to: "/workers", label: "Workers" },
  { to: "/shifts", label: "Shifts" },
  { to: "/schedules", label: "Schedules" },
  { to: "/calendar", label: "Calendar" },
];

export default function Sidebar() {
  return (
    <nav className="sidebar">
      {navItems.map((item) => (
        <NavLink
          key={item.to}
          to={item.to}
          end={item.end}
          className={({ isActive }) =>
            "sidebar-link" + (isActive ? " sidebar-link-active" : "")
          }
        >
          {item.label}
        </NavLink>
      ))}
    </nav>
  );
}
