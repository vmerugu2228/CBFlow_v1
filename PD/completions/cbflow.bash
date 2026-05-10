#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# CBflow v2.0.0 — Bash Shell Completions (RACE Engine)
# Source: source $CBFLOW_HOME/completions/cbflow.bash
# ══════════════════════════════════════════════════════════════════════════════

_cbflow_completions() {
    local cur prev words cword
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    cword=$COMP_CWORD

    # Level 1: main commands
    if [[ ${cword} -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "workspace run flow --version --help" -- "${cur}") )
        return 0
    fi

    local main_cmd="${COMP_WORDS[1]}"

    # Level 2: subcommands
    if [[ ${cword} -eq 2 ]]; then
        case "${main_cmd}" in
            workspace)
                COMPREPLY=( $(compgen -W "template create status list-runs clean validate" -- "${cur}") )
                ;;
            run)
                COMPREPLY=( $(compgen -W "all stage status retrace bypass force forcevalidate interactive clean validate logs report show-graph list-nodes add-node delete-node create-branch list-branches delete-branch release-info targets update email autoppt checklist help" -- "${cur}") )
                ;;
            flow)
                COMPREPLY=( $(compgen -W "types info stages nodes check version release config plugin metrics dashboard checklist qor-report trending library-manager mmmc-manager" -- "${cur}") )
                ;;
        esac
        return 0
    fi

    local sub_cmd="${COMP_WORDS[2]}"

    # Level 3+: options per subcommand
    case "${main_cmd}" in
        workspace)
            case "${sub_cmd}" in
                create)
                    case "${prev}" in
                        --config|-c) COMPREPLY=( $(compgen -f -X '!*.tcl' -- "${cur}") ) ;;
                        *)           COMPREPLY=( $(compgen -W "--config -c --force" -- "${cur}") ) ;;
                    esac ;;
                template)
                    case "${prev}" in
                        --flow)  COMPREPLY=( $(compgen -W "SYNTH FP PNR STA LEC EMIR PV ECO CLP POPT FCFP SYNTH_PNR" -- "${cur}") ) ;;
                        *)       COMPREPLY=( $(compgen -W "--flow --output" -- "${cur}") ) ;;
                    esac ;;
                clean) COMPREPLY=( $(compgen -W "--confirm" -- "${cur}") ) ;;
            esac ;;

        run)
            case "${sub_cmd}" in
                all)
                    COMPREPLY=( $(compgen -W "--validate --collect-metrics" -- "${cur}") ) ;;
                stage)
                    case "${prev}" in
                        --name|-n) COMPREPLY=( $(compgen -W "inputs1 init_design1 synthesis1 place1 cts1 cts_opt1 route1 pro1 signoff1 export_data1 release_data1" -- "${cur}") ) ;;
                        *)         COMPREPLY=( $(compgen -W "--name -n --validate" -- "${cur}") ) ;;
                    esac ;;
                status)
                    COMPREPLY=( $(compgen -W "--details -d --output -o" -- "${cur}") ) ;;
                retrace)
                    case "${prev}" in
                        --from) COMPREPLY=( $(compgen -W "inputs1 init_design1 synthesis1 place1 cts1 cts_opt1 route1 pro1 signoff1 export_data1 release_data1" -- "${cur}") ) ;;
                        *)      COMPREPLY=( $(compgen -W "--from --run" -- "${cur}") ) ;;
                    esac ;;
                bypass)
                    case "${prev}" in
                        --stages|-s|--node|-n) COMPREPLY=( $(compgen -W "inputs1 init_design1 synthesis1 place1 cts1 cts_opt1 route1 pro1 signoff1 export_data1 release_data1" -- "${cur}") ) ;;
                        *)                     COMPREPLY=( $(compgen -W "--stages -s" -- "${cur}") ) ;;
                    esac ;;
                force)
                    case "${prev}" in
                        --stages|-s|--node|-n) COMPREPLY=( $(compgen -W "inputs1 init_design1 synthesis1 place1 cts1 cts_opt1 route1 pro1 signoff1 export_data1 release_data1" -- "${cur}") ) ;;
                        *)                     COMPREPLY=( $(compgen -W "--stages -s" -- "${cur}") ) ;;
                    esac ;;
                forcevalidate)
                    case "${prev}" in
                        --node|-n|--from|--to) COMPREPLY=( $(compgen -W "inputs1 init_design1 synthesis1 place1 cts1 cts_opt1 route1 pro1 signoff1 export_data1 release_data1" -- "${cur}") ) ;;
                        *)                     COMPREPLY=( $(compgen -W "--node -n --from --to --stages -s" -- "${cur}") ) ;;
                    esac ;;
                email)
                    case "${prev}" in
                        --template|-t) COMPREPLY=( $(compgen -W "run-creation run-status run-summary checklist reminder release-update" -- "${cur}") ) ;;
                        --to)          COMPREPLY=() ;;
                        *)             COMPREPLY=( $(compgen -W "--to --template -t --subject -s --message -m --due-date --milestone --attach --preview --html" -- "${cur}") ) ;;
                    esac ;;
                autoppt)
                    case "${prev}" in
                        --format|-f) COMPREPLY=( $(compgen -W "pptx html" -- "${cur}") ) ;;
                        *)           COMPREPLY=( $(compgen -W "--format -f --output -o" -- "${cur}") ) ;;
                    esac ;;
                checklist)
                    case "${prev}" in
                        --milestone|-m) COMPREPLY=( $(compgen -W "FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO" -- "${cur}") ) ;;
                        --phase|-p)     COMPREPLY=( $(compgen -W "P0 P1 P2 P3" -- "${cur}") ) ;;
                        --format|-f)    COMPREPLY=( $(compgen -W "text json html" -- "${cur}") ) ;;
                        *)              COMPREPLY=( $(compgen -W "--milestone -m --phase -p --format -f --list --sign-off --approver --project" -- "${cur}") ) ;;
                    esac ;;
                interactive)
                    case "${prev}" in
                        --load|-l)
                            local nodes=""
                            if [[ -d "work" ]]; then
                                for d in work/*/; do
                                    for nd in ${d}*/; do
                                        [[ -d "$nd" ]] && nodes="$nodes $(basename $nd)"
                                    done
                                done
                            fi
                            COMPREPLY=( $(compgen -W "${nodes}" -- "${cur}") ) ;;
                        *) COMPREPLY=( $(compgen -W "--load -l" -- "${cur}") ) ;;
                    esac ;;
                show-graph)    COMPREPLY=( $(compgen -W "--detail -d" -- "${cur}") ) ;;
                add-node)      COMPREPLY=( $(compgen -W "--node -n --type -t --dep -d" -- "${cur}") ) ;;
                delete-node)   COMPREPLY=( $(compgen -W "--node -n" -- "${cur}") ) ;;
                create-branch) COMPREPLY=( $(compgen -W "--branch -b --from" -- "${cur}") ) ;;
                delete-branch) COMPREPLY=( $(compgen -W "--branch -b" -- "${cur}") ) ;;
                validate)
                    case "${prev}" in
                        --type)  COMPREPLY=( $(compgen -W "all config inputs exit" -- "${cur}") ) ;;
                        --stage) COMPREPLY=( $(compgen -W "inputs1 init_design1 synthesis1 place1 cts1 cts_opt1 route1 pro1 signoff1 export_data1 release_data1" -- "${cur}") ) ;;
                        *)       COMPREPLY=( $(compgen -W "--type --stage" -- "${cur}") ) ;;
                    esac ;;
                logs)
                    case "${prev}" in
                        --level) COMPREPLY=( $(compgen -W "DEBUG INFO WARNING ERROR" -- "${cur}") ) ;;
                        *)       COMPREPLY=( $(compgen -W "--list -l --tail --search -s --level --file -f" -- "${cur}") ) ;;
                    esac ;;
                report)
                    COMPREPLY=( $(compgen -W "--node -n --dump-setup --no-dump" -- "${cur}") ) ;;
                update)
                    case "${prev}" in
                        --release|-r) COMPREPLY=( $(compgen -W "v1.0.0 v1.0.1 v1.0.2" -- "${cur}") ) ;;
                        *)            COMPREPLY=( $(compgen -W "--release -r --no-backup" -- "${cur}") ) ;;
                    esac ;;
                lsf-status) COMPREPLY=( $(compgen -W "--flow" -- "${cur}") ) ;;
                clean)      COMPREPLY=( $(compgen -W "--confirm" -- "${cur}") ) ;;
            esac ;;

        flow)
            case "${sub_cmd}" in
                info|stages|nodes)
                    case "${prev}" in
                        --flow) COMPREPLY=( $(compgen -W "SYNTH FP PNR STA LEC EMIR PV ECO CLP POPT FCFP SYNTH_PNR" -- "${cur}") ) ;;
                        *)      COMPREPLY=( $(compgen -W "--flow" -- "${cur}") ) ;;
                    esac ;;
                version)
                    if [[ ${cword} -eq 3 ]]; then
                        COMPREPLY=( $(compgen -W "list copy set-current diff" -- "${cur}") )
                    fi ;;
                release)
                    if [[ ${cword} -eq 3 ]]; then
                        COMPREPLY=( $(compgen -W "create list info set-current validate diff" -- "${cur}") )
                    fi ;;
                checklist)
                    if [[ ${cword} -eq 3 ]]; then
                        COMPREPLY=( $(compgen -W "generate status sign-off list list-checks add-check remove-check waiver" -- "${cur}") )
                    else
                        case "${prev}" in
                            --milestone)    COMPREPLY=( $(compgen -W "FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO" -- "${cur}") ) ;;
                            --format)       COMPREPLY=( $(compgen -W "text json html" -- "${cur}") ) ;;
                            --check-type)   COMPREPLY=( $(compgen -W "mandatory optional file" -- "${cur}") ) ;;
                            --grep-pass-if) COMPREPLY=( $(compgen -W "found not_found" -- "${cur}") ) ;;
                            --action)       COMPREPLY=( $(compgen -W "list add revoke" -- "${cur}") ) ;;
                            *)              COMPREPLY=( $(compgen -W "--milestone --name --check-type --description --script --criteria --grep-file --grep-pattern --grep-pass-if --file-path --format --run-dir --project --phase --approver --action" -- "${cur}") ) ;;
                        esac
                    fi ;;
                library-manager)
                    if [[ ${cword} -eq 3 ]]; then
                        COMPREPLY=( $(compgen -W "scan check list generate-mmmc" -- "${cur}") )
                    fi ;;
                mmmc-manager)
                    if [[ ${cword} -eq 3 ]]; then
                        COMPREPLY=( $(compgen -W "create show validate" -- "${cur}") )
                    fi ;;
            esac ;;
    esac

    return 0
}

complete -F _cbflow_completions cbflow
