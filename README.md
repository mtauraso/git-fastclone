git-fastclone
=============

git clone --recursive on steroids

How to use?
----------

    gem install git-fastclone
    git fastclone ssh://git.url/repo.git

What does it do?
----------------
It creates a reference repo with `git clone --mirror` in `/var/tmp/git-fastclone/reference` for each repository and 
git submodule linked in the main repo. You can control where it puts these by changing the `REFERENCE_REPO_DIR` 
environment variable.

It aggressively updates these mirrors from origin and then clones from the mirrors into the directory of your 
choosing. It always works recursively and multithreaded to get your checkout up as fast as possible.
