defmodule SandboxCase.TestApp.Migration do
  use Ecto.Migration

  def change do
    create table(:items) do
      add(:name, :string)
    end

    # FunWithFlags Ecto backend table — the real adapter the sandbox
    # adapter delegates to when not sandboxed. (SQLite-flavoured; the
    # upstream template is Postgres :bigserial.)
    create table(:fun_with_flags_toggles) do
      add(:flag_name, :string, null: false)
      add(:gate_type, :string, null: false)
      add(:target, :string, null: false)
      add(:enabled, :boolean, null: false)
    end

    create(
      index(:fun_with_flags_toggles, [:flag_name, :gate_type, :target],
        unique: true,
        name: "fwf_flag_name_gate_target_idx"
      )
    )
  end
end
