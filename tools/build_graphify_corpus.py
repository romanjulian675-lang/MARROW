from __future__ import annotations

import argparse
import re
import shutil
from dataclasses import dataclass, field
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / "graphify-corpus"


SCRIPT_DIRS = [ROOT / "scripts"]
SCENE_DIRS = [ROOT / "scenes"]
DOC_DIRS = [ROOT / "docs"]
PROJECT_FILES = [ROOT / "project.godot", ROOT / "README.md", ROOT / "AGENTS.md"]


CLASS_RE = re.compile(r"^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)
EXTENDS_RE = re.compile(r"^\s*extends\s+([A-Za-z_][A-Za-z0-9_./\"]*)", re.MULTILINE)
SIGNAL_RE = re.compile(r"^\s*signal\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:\(([^)]*)\))?", re.MULTILINE)
EXPORT_RE = re.compile(r"^\s*@export(?:_[A-Za-z0-9_]+)?(?:\([^)]*\))?\s+var\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)
CONST_RE = re.compile(r"^\s*const\s+([A-Z][A-Z0-9_]*)", re.MULTILINE)
VAR_RE = re.compile(r"^\s*var\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)
FUNC_RE = re.compile(r"^\s*func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*(?:->\s*([^:]+))?:", re.MULTILINE)
PRELOAD_RE = re.compile(r"\bpreload\(\"(res://[^\"]+)\"\)")
LOAD_RE = re.compile(r"\bload\(\"(res://[^\"]+)\"\)")
GAME_EVENTS_RE = re.compile(r"\bGameEvents\.([A-Za-z_][A-Za-z0-9_]*)")
INPUT_ACTION_RE = re.compile(r"\b(?:Input\.|InputMap\.)[A-Za-z_][A-Za-z0-9_]*\(\"([A-Za-z0-9_]+)\"")
GET_NODE_RE = re.compile(r"\b(?:get_node|get_node_or_null)\(\"([^\"]+)\"\)")


@dataclass
class ScriptInfo:
    path: Path
    rel: str
    text: str
    class_name: str = ""
    extends: str = ""
    signals: list[str] = field(default_factory=list)
    exports: list[str] = field(default_factory=list)
    constants: list[str] = field(default_factory=list)
    variables: list[str] = field(default_factory=list)
    functions: list[str] = field(default_factory=list)
    dependencies: list[str] = field(default_factory=list)
    game_events: list[str] = field(default_factory=list)
    input_actions: list[str] = field(default_factory=list)
    node_paths: list[str] = field(default_factory=list)


@dataclass
class SceneInfo:
    path: Path
    rel: str
    text: str
    scripts: list[str] = field(default_factory=list)
    packed_scenes: list[str] = field(default_factory=list)
    nodes: list[str] = field(default_factory=list)


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def unique(values: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for value in values:
        if value and value not in seen:
            seen.add(value)
            result.append(value)
    return result


def res_to_repo_path(value: str) -> str:
    if value.startswith("res://"):
        return value.replace("res://", "", 1)
    return value


def parse_script(path: Path) -> ScriptInfo:
    text = read_text(path)
    info = ScriptInfo(path=path, rel=rel(path), text=text)
    info.class_name = first_match(CLASS_RE, text)
    info.extends = first_match(EXTENDS_RE, text)
    info.signals = unique([format_signature(name, args) for name, args in SIGNAL_RE.findall(text)])
    info.exports = unique(EXPORT_RE.findall(text))
    info.constants = unique(CONST_RE.findall(text))
    info.variables = unique(VAR_RE.findall(text))
    info.functions = unique([format_function(name, args, ret) for name, args, ret in FUNC_RE.findall(text)])
    info.dependencies = unique([res_to_repo_path(v) for v in PRELOAD_RE.findall(text) + LOAD_RE.findall(text)])
    info.game_events = unique(GAME_EVENTS_RE.findall(text))
    info.input_actions = unique(INPUT_ACTION_RE.findall(text))
    info.node_paths = unique(GET_NODE_RE.findall(text))
    return info


def parse_scene(path: Path) -> SceneInfo:
    text = read_text(path)
    info = SceneInfo(path=path, rel=rel(path), text=text)
    for match in re.finditer(r'\[ext_resource[^\]]*type="Script"[^\]]*path="([^"]+)"[^\]]*id="([^"]+)"', text):
        info.scripts.append(res_to_repo_path(match.group(1)))
    for match in re.finditer(r'\[ext_resource[^\]]*type="PackedScene"[^\]]*path="([^"]+)"[^\]]*id="([^"]+)"', text):
        info.packed_scenes.append(res_to_repo_path(match.group(1)))
    info.scripts = unique(info.scripts)
    info.packed_scenes = unique(info.packed_scenes)
    info.nodes = unique(re.findall(r'\[node\s+name="([^"]+)"', text))
    return info


def first_match(pattern: re.Pattern[str], text: str) -> str:
    match = pattern.search(text)
    return match.group(1) if match else ""


def format_signature(name: str, args: str) -> str:
    args = " ".join(args.split())
    return f"{name}({args})" if args else f"{name}()"


def format_function(name: str, args: str, ret: str) -> str:
    args = " ".join(args.split())
    ret = ret.strip()
    suffix = f" -> {ret}" if ret else ""
    return f"{name}({args}){suffix}"


def md_list(values: list[str], empty: str = "none") -> str:
    if not values:
        return f"- {empty}\n"
    return "".join(f"- `{value}`\n" for value in values)


def collect_files() -> tuple[list[ScriptInfo], list[SceneInfo], list[Path], list[Path]]:
    scripts = [parse_script(path) for base in SCRIPT_DIRS for path in sorted(base.rglob("*.gd"))]
    scenes = [parse_scene(path) for base in SCENE_DIRS for path in sorted(base.rglob("*.tscn"))]
    docs = [path for base in DOC_DIRS for path in sorted(base.rglob("*.md"))]
    project_files = [path for path in PROJECT_FILES if path.exists()]
    return scripts, scenes, docs, project_files


def build_class_lookup(scripts: list[ScriptInfo]) -> dict[str, ScriptInfo]:
    return {info.class_name: info for info in scripts if info.class_name}


def infer_script_edges(scripts: list[ScriptInfo], class_lookup: dict[str, ScriptInfo]) -> list[tuple[str, str, str]]:
    edges: list[tuple[str, str, str]] = []
    for source in scripts:
        for dep in source.dependencies:
            edges.append((source.rel, dep, "loads resource"))
        for class_name, target in class_lookup.items():
            if source.rel == target.rel:
                continue
            if re.search(rf"\b{re.escape(class_name)}\b", source.text):
                edges.append((source.rel, target.rel, f"references class {class_name}"))
    return unique_edges(edges)


def infer_scene_edges(scenes: list[SceneInfo]) -> list[tuple[str, str, str]]:
    edges: list[tuple[str, str, str]] = []
    for scene in scenes:
        for script in scene.scripts:
            edges.append((scene.rel, script, "uses script"))
        for packed_scene in scene.packed_scenes:
            edges.append((scene.rel, packed_scene, "instantiates scene"))
    return unique_edges(edges)


def unique_edges(edges: list[tuple[str, str, str]]) -> list[tuple[str, str, str]]:
    seen: set[tuple[str, str, str]] = set()
    result: list[tuple[str, str, str]] = []
    for edge in edges:
        if edge not in seen:
            seen.add(edge)
            result.append(edge)
    return result


def system_for_path(path: str) -> str:
    name = Path(path).name
    if "inventory" in name or "equipment" in name or "bone" in name:
        return "Inventory, equipment, and bones"
    if "enemy" in name or "attack" in name or "projectile" in name:
        return "Combat and enemies"
    if "camera" in name:
        return "Camera and controls"
    if "rig" in path or "animator" in name:
        return "Rig and animation"
    if "world" in name or "arena" in name or "stage" in name or "portal" in name:
        return "World, goals, and progression"
    if "ui" in name or "wisp" in name:
        return "UI and guidance"
    if name == "player.gd":
        return "Player orchestration"
    return "Supporting gameplay"


def write_index(out_dir: Path, scripts: list[ScriptInfo], scenes: list[SceneInfo], docs: list[Path], project_files: list[Path]) -> None:
    lines = [
        "# Marrow Graphify Corpus\n",
        "\n",
        "This generated corpus translates the Godot project into Markdown that Graphify can map reliably.\n",
        "It is derived from source files and should be rebuilt before Graphify runs.\n",
        "\n",
        "## Included Source\n",
        f"- GDScript files: {len(scripts)}\n",
        f"- Godot scenes: {len(scenes)}\n",
        f"- Documentation files: {len(docs)}\n",
        f"- Project/root files: {len(project_files)}\n",
        "\n",
        "## Generated Maps\n",
        "- `gdscript-api.md`: classes, functions, signals, exports, dependencies, input actions, and GameEvents usage.\n",
        "- `scene-map.md`: scenes, node names, and attached scripts.\n",
        "- `dependency-map.md`: inferred relationships between scripts and scenes.\n",
        "- `system-map.md`: project systems grouped by gameplay responsibility.\n",
        "- `source-docs.md`: source documentation included in the graph.\n",
    ]
    (out_dir / "index.md").write_text("".join(lines), encoding="utf-8")


def write_gdscript_api(out_dir: Path, scripts: list[ScriptInfo]) -> None:
    lines = ["# GDScript API Map\n\n"]
    for info in scripts:
        title = info.class_name or Path(info.rel).stem
        lines.append(f"## {title}\n\n")
        lines.append(f"- Source file: `{info.rel}`\n")
        lines.append(f"- Extends: `{info.extends or 'unknown'}`\n")
        lines.append(f"- System: {system_for_path(info.rel)}\n")
        lines.append("\n### Signals\n")
        lines.append(md_list(info.signals))
        lines.append("\n### Exported Tuning\n")
        lines.append(md_list(info.exports))
        lines.append("\n### Constants\n")
        lines.append(md_list(info.constants[:30]))
        lines.append("\n### Key Variables\n")
        lines.append(md_list(info.variables[:40]))
        lines.append("\n### Functions\n")
        lines.append(md_list(info.functions))
        lines.append("\n### Resource Dependencies\n")
        lines.append(md_list(info.dependencies))
        lines.append("\n### GameEvents Usage\n")
        lines.append(md_list(info.game_events))
        lines.append("\n### Input Actions\n")
        lines.append(md_list(info.input_actions))
        lines.append("\n### Node Path Lookups\n")
        lines.append(md_list(info.node_paths[:40]))
        lines.append("\n")
    (out_dir / "gdscript-api.md").write_text("".join(lines), encoding="utf-8")


def write_scene_map(out_dir: Path, scenes: list[SceneInfo]) -> None:
    lines = ["# Godot Scene Map\n\n"]
    for scene in scenes:
        lines.append(f"## {scene.rel}\n\n")
        lines.append("### Attached Scripts\n")
        lines.append(md_list(scene.scripts))
        lines.append("\n### Instanced Scenes\n")
        lines.append(md_list(scene.packed_scenes))
        lines.append("\n### Nodes\n")
        lines.append(md_list(scene.nodes[:80]))
        lines.append("\n")
    (out_dir / "scene-map.md").write_text("".join(lines), encoding="utf-8")


def write_dependency_map(out_dir: Path, script_edges: list[tuple[str, str, str]], scene_edges: list[tuple[str, str, str]]) -> None:
    lines = ["# Dependency Map\n\n"]
    lines.append("## Script Relationships\n\n")
    if script_edges:
        for source, target, reason in script_edges:
            lines.append(f"- `{source}` depends on `{target}` because it {reason}.\n")
    else:
        lines.append("- none\n")
    lines.append("\n## Scene Relationships\n\n")
    if scene_edges:
        for source, target, reason in scene_edges:
            lines.append(f"- `{source}` {reason} `{target}`.\n")
    else:
        lines.append("- none\n")
    (out_dir / "dependency-map.md").write_text("".join(lines), encoding="utf-8")


def write_system_map(out_dir: Path, scripts: list[ScriptInfo], scenes: list[SceneInfo]) -> None:
    systems: dict[str, list[str]] = {}
    for info in scripts:
        systems.setdefault(system_for_path(info.rel), []).append(info.rel)
    lines = ["# Marrow System Map\n\n"]
    for system in sorted(systems):
        lines.append(f"## {system}\n\n")
        for path in systems[system]:
            lines.append(f"- `{path}`\n")
        lines.append("\n")
    lines.append("## Scene Entry Points\n\n")
    for scene in scenes:
        if scene.scripts:
            lines.append(f"- `{scene.rel}` composes {', '.join(f'`{script}`' for script in scene.scripts)}.\n")
    (out_dir / "system-map.md").write_text("".join(lines), encoding="utf-8")


def write_source_docs(out_dir: Path, docs: list[Path], project_files: list[Path]) -> None:
    lines = ["# Source Documentation Index\n\n"]
    for path in project_files + docs:
        lines.append(f"## {rel(path)}\n\n")
        text = read_text(path)
        lines.append(text.strip())
        lines.append("\n\n")
    (out_dir / "source-docs.md").write_text("".join(lines), encoding="utf-8")


def build(out_dir: Path) -> None:
    scripts, scenes, docs, project_files = collect_files()
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    class_lookup = build_class_lookup(scripts)
    script_edges = infer_script_edges(scripts, class_lookup)
    scene_edges = infer_scene_edges(scenes)
    write_index(out_dir, scripts, scenes, docs, project_files)
    write_gdscript_api(out_dir, scripts)
    write_scene_map(out_dir, scenes)
    write_dependency_map(out_dir, script_edges, scene_edges)
    write_system_map(out_dir, scripts, scenes)
    write_source_docs(out_dir, docs, project_files)
    print(f"Graphify corpus written to {out_dir.relative_to(ROOT).as_posix()}")
    print(f"Scripts: {len(scripts)} | Scenes: {len(scenes)} | Docs/root files: {len(docs) + len(project_files)}")
    print(f"Script edges: {len(script_edges)} | Scene edges: {len(scene_edges)}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Build a Graphify-friendly Markdown corpus for the Marrow Godot project.")
    parser.add_argument("--out", default=str(DEFAULT_OUT), help="Output directory for generated corpus.")
    args = parser.parse_args()
    build(Path(args.out).resolve())


if __name__ == "__main__":
    main()
