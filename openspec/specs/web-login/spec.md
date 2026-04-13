## Requirements

### Requirement: Login page
The frontend SHALL display a login page when the user has no valid session token in `sessionStorage`.

#### Scenario: Fresh visit
- **WHEN** a user navigates to the application with no token in `sessionStorage`
- **THEN** the login page is displayed with username and password fields and a submit button

#### Scenario: Successful login
- **WHEN** the user enters valid credentials and submits the login form
- **THEN** the frontend POSTs `{"username": "<username>", "password": "<password>"}` to `/api/login`
- **AND** stores the returned token in `sessionStorage`
- **AND** navigates to the terminal view

#### Scenario: Failed login
- **WHEN** the user enters invalid credentials and submits the login form
- **THEN** the frontend displays an error message (e.g., "Invalid username or password")
- **AND** does not store a token or navigate away from the login page

### Requirement: Logout
The frontend SHALL provide a logout control that ends the session.

#### Scenario: User logs out
- **WHEN** the user clicks the logout button
- **THEN** the frontend POSTs to `/api/logout` with the current token
- **AND** removes the token from `sessionStorage`
- **AND** returns to the login page

### Requirement: Session expiry handling
The frontend SHALL handle session expiry by returning to the login page.

#### Scenario: Expired session
- **WHEN** any API call returns HTTP 401
- **THEN** the frontend removes the token from `sessionStorage`
- **AND** returns to the login page
