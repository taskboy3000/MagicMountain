Controller Architecture Review

After reviewing the controller layer, I believe the project is beginning to drift away from one of its core architectural principles.

The goal of this refactoring is not to move code around simply to make controllers shorter. The goal is to restore the intended layering of the application.

Desired Controller Responsibilities

Controllers should be thin HTTP adapters.

A controller should primarily:

1. Extract information from the HTTP request/session.
2. Locate the appropriate domain object or service.
3. Invoke a small number of model/service methods.
4. Stash the returned view model.
5. Render the response.

Controllers should not contain game rules, business decisions, recommendation logic, market calculations, recap generation, navigation policy, or view-model assembly.

If a controller needs several private helper methods to compute application state, that logic almost certainly belongs somewhere else.

Refactoring Priorities

Highest Priority

Season.pm

The season recap has become one of the signature features of Magic Mountain.

The controller currently owns too much of the recap generation process.

Please extract a SeasonRecap (or similarly named) service whose responsibility is:

* determine season facts
* assemble recap context
* choose recap fragments
* return a finished recap model

The controller should simply request the recap and render it.

⸻

Game.pm

This controller currently appears to be acting as an application service.

It performs startup work, reconstructs application state, assembles multiple view models, and coordinates numerous pieces of game state.

This orchestration belongs in a dedicated model/service.

The controller should become a thin façade over that object.

⸻

Nav.pm

Navigation has become a fictional application running inside the ProspectBoy 3000.

That is now domain logic.

Please extract the PB3K navigation rules into a dedicated navigation model/service.

Controllers should not decide navigation policy.

⸻

Medium Priority

Home.pm

Suggestion generation is game design.

Move recommendation logic into a reusable service that returns player suggestions.

The controller should simply request those suggestions.

⸻

Market.pm

Customer mood, pressure state, buyer presentation, and other market-derived display information should come from the market model/activity rather than being calculated inside the controller.

The controller should coordinate, not interpret.

⸻

Skills.pm

Skill purchase validation and resource mutation belong in the domain layer.

The controller should request “train this skill” and receive success/failure.

Architectural Principle

Please continue following the project’s data-driven philosophy.

Controllers should assemble almost no data themselves.

Instead:

HTTP Request
→ Domain Models
→ View Model Builder
→ Controller
→ Template

The controller should not become another business layer.

AGENTS.md Recommendation

I recommend adding the following permanent guidance.

Controllers

Controllers are HTTP adapters only.

Controllers MUST NOT:

* implement game rules
* calculate derived game state
* build recommendation engines
* assemble narrative
* determine navigation policy
* mutate domain objects except through model/service APIs

Controllers SHOULD:

* extract HTTP parameters
* invoke domain services
* stash returned view models
* render templates

If a controller grows multiple private helper methods that calculate game state, stop and create a model/service instead.

Long-Term Goal

The objective is not “small controllers.”

The objective is a system where the game can be exercised from simulations, bots, command-line tools, and future front ends (web, mobile, CLI) because the business logic lives entirely in the domain layer.

The web controllers should become one of many possible interfaces into the game engine, not the place where the game engine lives.

