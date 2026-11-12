// The words this repository's commands are started with, refused as the
// declared layer `wisent_errors.lint.arguments` says: no command, an unknown
// one, an option without its value, an option the command does not have, the
// wrong number of operands.

import { refuse } from './refuse.mjs';

const ARGUMENTS = 'wisent_errors.lint.arguments';

/** One command line: the program's name, its usage text and its commands. */
export class Words {
  constructor(program, usage, words, commands = []) {
    this.program = program;
    this.usage = usage;
    this.words = [...words];
    this.commands = commands;
    this.given = words.join(' ') || '(none)';
  }

  /** The command word, refused when absent or unknown. */
  command() {
    const [command] = this.words.splice(0, 1);
    const values = { program: this.program, commands: this.commands.join(', '), usage: this.usage };
    if (command === undefined) refuse(ARGUMENTS, 'command-absent', values);
    if (!this.commands.includes(command)) refuse(ARGUMENTS, 'command-unknown', { ...values, quoted_command: JSON.stringify(command) });
    return command;
  }

  /** Whether `flag` was given, removing it. */
  flag(flag) {
    const at = this.words.indexOf(flag);
    if (at < 0) return false;
    this.words.splice(at, 1);
    return true;
  }

  /** The value after `flag`, removing both, or null when the flag is absent. */
  option(flag) {
    const at = this.words.indexOf(flag);
    if (at < 0) return null;
    const value = this.words[at + 1];
    if (value === undefined || value.startsWith('--')) {
      refuse(ARGUMENTS, 'option-without-value', { program: this.program, option: flag, words: this.given, usage: this.usage });
    }
    this.words.splice(at, 2);
    return value;
  }

  /**
   * The operands left, refused unless `accept(count)`; `expected` says what is
   * accepted. A word still starting with `--` here is an option the command
   * read none of, refused by name before anything is counted.
   */
  operands(expected, accept) {
    const unknown = this.words.find((word) => word.startsWith('--'));
    if (unknown !== undefined) refuse(ARGUMENTS, 'option-unknown', { program: this.program, option: unknown, words: this.given, usage: this.usage });
    if (!accept(this.words.length)) {
      refuse(ARGUMENTS, 'operands-miscounted', {
        program: this.program,
        expected,
        count: String(this.words.length),
        operands: this.words.length ? this.words.join(' ') : '(none)',
        usage: this.usage,
      });
    }
    return this.words;
  }
}
