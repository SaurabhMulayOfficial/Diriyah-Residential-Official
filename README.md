# Contribution Guide

Thank you for contributing! Please follow the branching and deployment strategy outlined below.

---

## 🌳 Branching Strategy

We maintain two primary branches:

- **`main`** – Production branch  
- **`develop`** – Integration branch (UAT-ready code)

---

## 🚀 Development Workflow

### 1️⃣ Create QA Feature Branch

- Create all **`feature/QADIR/**`** branches from **`develop`**.
- These branches are used for QA-level development and testing.

```bash
git checkout develop
git pull origin develop
git checkout -b feature/QADIR/your-feature-name
```

---

### 2️⃣ Create Sub-Feature Branch (Optional)

If required, you may create additional **`feature/**`** branches from an existing **`feature/QADIR/**`** branch.

```bash
git checkout feature/QADIR/your-feature-name
git checkout -b feature/your-sub-task
```

- Merge sub-feature branches back into the parent **`feature/QADIR/**`** branch.
- ✅ Once merged, changes are automatically deployed to the **QA environment**.

---

### 3️⃣ Promote to UAT

- When a **`feature/QADIR/**`** branch is merged into **`develop`**:
  - 🚀 Deployment is automatically triggered to the **UAT environment**.

---

### 4️⃣ Production Release

- The **`main`** branch represents Production.
- Code is promoted to `main` as part of the official release process.

---

## 🔁 Deployment Flow

```
develop
   ↓
feature/QADIR/*
   ↓
feature/* (optional)
   ↓ (merge back)
feature/QADIR/* → Auto Deploy to QA
   ↓ (merge to develop)
develop → Auto Deploy to UAT
   ↓
main → Production
```

---

## 📌 Important Rules

- Always branch from the correct base branch.
- Keep pull requests small and focused.
- Ensure all checks pass before requesting a merge.
- Do not commit directly to `main` or `develop`.
- Follow naming conventions strictly.

---

## ✅ Branch Naming Convention

| Branch Type | Format |
|-------------|--------|
| QA Feature  | `feature/QADIR/feature-name` |
| Sub-Feature | `feature/feature-name` |

---
