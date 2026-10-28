# BranchFlow 📚⚡

> **A real-time cross-branch return and inventory transit app for community library networks.**

---

## 🎯 Problem Statement
A network of community libraries allows members to borrow books from any branch, but each branch maintains its own catalog independently. A book returned to a different branch disappears from the borrowing record for days, and members face holds or penalties for items they have already returned.

---

## 💡 Solution Overview
**BranchFlow** bridges catalog silos by introducing a unified real-time ledger on Cloud Firestore and camera-driven barcode/QR check-ins:
1. **Instant Loan Discharge:** When a book is returned to *any* branch, scanning it immediately marks the member's loan as returned at that exact timestamp, instantly freezing penalties and clearing borrowing holds.
2. **Decoupled Transit Pipeline:** Physical book relocation is tracked via an inter-branch transit queue (`Holding at Drop-off Branch` ➔ `In-Transit with Courier` ➔ `Re-shelved at Home Branch`) without penalizing the borrower.
3. **Digital Return Receipt:** Issues immediate in-app proof of return with branch ID, timestamp, and staff verification.

---

## 👥 Target Users
1. **Library Members:** Borrowers who want the flexibility to return books at whichever branch is closest to them without risking wrongful fines, delayed clearances, or blocked accounts.
2. **Branch Librarians & Desk Staff:** Staff receiving drop-offs belonging to other branches who need instant scan-to-return capability and an organized transit staging dispatch.
3. **Inter-Branch Couriers & Network Admins:** Personnel responsible for moving batches of cross-branch books between locations and reconciling inter-branch inventory.

---

## 🛠️ Tech Stack & Architecture
- **Framework:** Flutter (Android / iOS / Web)
- **Backend & Database:** Firebase Cloud Firestore (Real-time synchronization across branch nodes)
- **Authentication:** Firebase Auth (Role-based access: Member vs. Staff/Admin)
- **Scanning Engine:** `mobile_scanner` (Fast ISBN & Library Asset Barcode/QR scanning)
- **Storage:** Firebase Storage (Book covers and digital signed return receipts)

---

## 📋 Team Charter

| Role / Category | Details |
|---|---|
| **App Name** | **BranchFlow** |
| **Team Name** | BranchFlow Core Team |
| **Project Admin** | Sujal Rana (`@sujal-rana58`) |
| **Team Members & Responsibilities** | • **Project Admin / State & Routing:** Architecture, GitHub PRs, Navigation<br>• **Frontend / Mobile UI:** Screens (Dashboard, Scanner, Receipts, Loan History)<br>• **Backend / Firebase:** Firestore Collections, Auth, Security Rules, Real-Time Streams<br>• **Logistics & QA:** Mobile Scanner integration, transit state machine, emulator testing |
| **Core Working Agreements** | • Daily Standup: 10:00 AM<br>• PR Submission Deadline: Daily by 6:00 PM<br>• Code Review SLA: Review within 2 hours of PR opening<br>• Definition of Done: Code runs on mobile emulator/device + no lint errors + tested against Firestore |
| **Communication Channel** | Slack / Discord / WhatsApp group |
| **Branching Strategy** | `main` (Protected) ➔ Feature branches (`feature/auth`, `feature/scanner`, `feature/transit`) ➔ PR Review ➔ Merge |

---

## 🗺️ 5-Week Sprint Roadmap

- **Week 1 (Discovery & Setup):** PRD, Firestore System Design & Schema approval, Flutter skeleton initialization.
- **Week 2 (Core Auth & Catalog):** Multi-branch authentication (Member vs. Staff), branch catalog browsing, and basic checkout tracking.
- **Week 3 (Cross-Branch Return & Scanner):** `mobile_scanner` integration, instant loan discharge logic, penalty freeze timestamping.
- **Week 4 (Transit & Reconciliation Hub):** Dispatch queue, courier transit batching, home-branch restocking verification, and digital receipt generation.
- **Week 5 (Security Rules, Polish & Showcase):** Firestore Security Rules enforcement, offline persistence, UI polishing, and final demo showcase.

---

## 📖 Sprint 2 Deliverables & Documentation Links

Every requirement for the **Sprint 2 Final Submission** is documented and version-controlled:

- 📋 **[Product Requirements Document (PRD)](docs/PRD.md):** 10-section comprehensive PRD detailing problem statement, user personas, screen flows, Firestore schema, out-of-scope boundaries, and definition of done.
- 🎨 **[Mock UX & Wireframes (MOCK_UX.md)](docs/MOCK_UX.md):** Detailed wireframe layouts, 5 user modes, transition states, and edge/empty/error cases.
- 🏗️ **[Architecture & Concepts Guide](docs/ARCHITECTURE_AND_CONCEPTS.md):** Deep-dive technical explanations for all 40 Sprint concepts (Stateful vs Stateless, Auth Streams, Storage, CRUD, Server Timestamps, Security Rules).
- 🔒 **[Firestore Security Rules](firestore.rules):** Enforces role-based permissions (`request.auth.uid`, `isLibrarian()`, loan immutability).
- 🗄️ **[Storage Security Rules](storage.rules):** Restricts receipt proof and book cover uploads (`5MB max`, `image/*` MIME check).
- 🚀 **[Production Setup & Deployment Runbook](docs/PRODUCTION_SETUP_GUIDE.md):** Complete step-by-step guide to connect a live Google Firebase cloud project, deploy rules & indexes, seed initial data, and build release APK/AAB binaries.

---

## 🚀 Getting Started & How to Run

### 1. Prerequisites
- Flutter SDK (v3.22.0 or higher)
- Dart SDK (v3.4.0 or higher)

### 2. Installation
```bash
git clone https://github.com/sujal-rana58/BranchFlow.git
cd BranchFlow
flutter pub get
```

### 3. Run the App
BranchFlow features an intelligent dual-mode architecture: it connects to Firebase if credentials exist, and automatically falls back to an in-memory reactive state with 4 seeded branches and real catalog books.
```bash
# Run on Windows Desktop
flutter run -d windows

# Run on Chrome Web
flutter run -d chrome

# Run on Android / iOS
flutter run
```

### 4. Running Automated Tests & Analyzer
```bash
# Run all 11 unit, widget, and model tests (100% passing)
flutter test

# Run static code analysis (0 errors, 0 warnings, 0 deprecations)
flutter analyze
```

---

## 🧪 Interactive Testing & Evaluation Walkthrough

BranchFlow contains built-in test fixtures and simulators so you can evaluate all features on desktop, browser, or emulator:

### 1. Instant Demo Login (Auth & Persistent Session)
- On the launch screen, tap **"Quick Fill Member"** (`member@branchflow.lib` / `password123`) or **"Quick Fill Librarian"** (`staff@branchflow.lib` / `password123`).
- Tap **Sign Up** with a real email address: a 6-digit code is emailed to you and must be entered to reach the dashboard.
- Tap **Forgot Password** to get a reset code by email and set a new password.
- Both need the Cloud Functions deployed and SMTP configured. See Step 7 of [docs/PRODUCTION_SETUP_GUIDE.md](docs/PRODUCTION_SETUP_GUIDE.md).

### 2. Cross-Branch Return Desk (The Problem Solver)
1. Switch to the **Return Desk** tab (barcode icon).
2. The drop-down shows the currently active return branch (e.g., **Westside Community Library**).
3. Tap any book under **"Test Barcode Simulator"** (e.g., *Clean Code*, whose home branch is Central).
4. **Immediate Result:** 
   - A digital **Verified Return Certificate** appears.
   - Borrower liability is instantly cleared at the exact current timestamp.
   - Accruing fines/penalties are frozen to **$0.00**.
   - The book is safely queued into **Holding Staging** at Westside rather than disappearing into a void!

### 3. Courier Transit Hub (Physical Rebalancing)
1. Switch to the **Transit Hub** tab.
2. Under **Holding Staging**, tap **"Dispatch with Courier"** to assign a batch code and put it in transit.
3. Under **In Transit**, tap **"Mark Restocked"** when the courier reaches the home branch (Central).
4. The book's status returns to **Available** at Central Library with zero inventory discrepancies.

### 4. Unified Catalog Search & Multi-Branch Filters
- Search by keyword or author (real-time `onChanged` filter).
- Tap branch chips (**Central**, **North**, **West**, **East**) or status chips (**Available**, **Borrowed**, **In Holding**) to test multi-tier filtering.

---

## 🔧 Troubleshooting Common Flutter Issues

- **Port or process lock on Windows**:
  ```powershell
  flutter clean
  flutter pub get
  ```
- **Run on a specific browser if Chrome isn't default**:
  ```powershell
  flutter run -d edge
  # or
  flutter run -d windows
  ```
- **Firebase Connection Optionality**:
  The application runs out of the box in **Offline-First Reactive Mode** with complete mock branches and inventory. To link your own live Google Cloud Firebase project, simply run `flutterfire configure` to generate `lib/firebase_options.dart`.

---

## 🏆 Final Submission Checklist (SR 3.49)

- [x] **10+ PRs / Distributed Commits:** Scoped commits across features (Auth, Firestore CRUD, Mobile Scanner, Transit Hub, UI Polish).
- [x] **PRD Present:** Available in [`docs/PRD.md`](docs/PRD.md).
- [x] **Mock UX Present:** Available in [`docs/MOCK_UX.md`](docs/MOCK_UX.md).
- [x] **README Maintained:** Clear problem description, setup steps, test execution, troubleshooting, and architecture overview.
